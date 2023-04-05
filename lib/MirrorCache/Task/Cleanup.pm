# Copyright (C) 2021 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

package MirrorCache::Task::Cleanup;
use Mojo::Base 'Mojolicious::Plugin';
use MirrorCache::Utils 'datetime_now';

sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(cleanup => sub { _run($app, @_) });
}

my $DELAY          = int($ENV{MIRRORCACHE_SCHEDULE_CLEANUP_RETRY_INTERVAL} // 2 * 60);
my $STAT_KEEP_DAYS = int($ENV{MIRRORCACHE_STAT_KEEP_DAYS} // 8) // 8;

sub _run {
    my ($app, $job) = @_;
    my $minion = $app->minion;
    return $job->finish('Previous cleanup job is still active')
      unless my $guard = $minion->guard('cleanup', 120);

    my $schema = $app->schema;
    $minion->enqueue('mirror_probe_projects');

    # detect stalled backstage jobs
    my $sql;
    if ($schema->pg) {
$sql = <<'END_SQL';
update minion_jobs set state = 'failed', result = '"killed"' where state = 'active' and started < now() - interval '1 hour'
END_SQL
    } else {
$sql = <<'END_SQL';
update minion_jobs set state = 'failed', result = '"killed"' where state = 'active' and started < now() - interval 1 hour
END_SQL
}
    eval {
        $schema->storage->dbh->prepare($sql)->execute();
        1;
    } or $job->note(last_warning_0 => $@, at_0 => datetime_now());

    eval {
        if ($schema->pg) {
$sql = <<'END_SQL';
with DiffToDelete as (
   select fd.id
   from folder_diff fd
   left join folder_diff_server fds on fds.folder_diff_id = fd.id
   where
   fds.folder_diff_id is null
   and fd.dt < current_timestamp - interval '2 day'
   limit 1000
 ),
FilesDeleted as (
   delete from folder_diff_file where folder_diff_id in
   (select * from DiffToDelete))
delete from folder_diff where id in
   (select * from DiffToDelete)
END_SQL
            $schema->storage->dbh->prepare($sql)->execute();
            1;
        } else {
        # delete query with will lock a lot of rows, so we split it into select + deletes
$sql = <<'END_SQL';
select fd.id from folder_diff fd
left join folder_diff_server fds on fds.folder_diff_id = fd.id
where
fds.folder_diff_id is null
and fd.dt < date_sub(CURRENT_TIMESTAMP(3), interval 2 day)
limit 1000
END_SQL
            my $ids_to_delete = $schema->storage->dbh->prepare($sql);
            $ids_to_delete->execute();
            my $delete = $schema->storage->dbh->prepare('delete from folder_diff where id = ?');
            while (my @row = $ids_to_delete->fetchrow_array()) {
                my ($id) = @row;
                $delete->execute($id) if $id;
            }
        }
    } or $job->note(last_warning_1 => $@, at_1 => datetime_now());
    # delete rows from server_capability_check to avoid overload
    my $sqlservercap;
    if ($schema->pg) {
$sqlservercap = <<'END_SQL';
delete from server_capability_check
where ctid in (
   select ctid from server_capability_check
   where dt < (current_timestamp - interval '14 day')
   LIMIT 1000
)
END_SQL
    } else {
        $sqlservercap = "delete from server_capability_check where dt < date_sub(current_timestamp, interval 14 day) LIMIT 1000";
    }
    eval {
        $schema->storage->dbh->prepare($sqlservercap)->execute();
        1;
    } or $job->note(last_warning_2 => $@, at_2 => datetime_now());

    # delete rows from audit_event
    my $fail_count;
    my $last_warning;
    eval {
        ($fail_count, $last_warning) = $schema->resultset('AuditEvent')->cleanup_audit_events($app);
        $fail_count ? 0 : 1;
    } or $job->note(last_warning_3 => $last_warning, delete_fail_count => $fail_count, at_3 => datetime_now());

    # delete rows from stat
    my $sqlstat;
    if ($schema->pg) {
$sqlservercap = <<END_SQL;
delete from stat
where ctid in (
   select ctid from stat
   where dt < (current_timestamp - interval '$STAT_KEEP_DAYS day')
   LIMIT 100000
)
END_SQL
    } else {
        $sqlservercap = "delete from stat where dt < date_sub(current_timestamp, interval $STAT_KEEP_DAYS day) LIMIT 100000";
    }
    eval {
        $schema->storage->dbh->prepare($sqlservercap)->execute();
        1;
    } or $job->note(last_warning_4 => $@, at_4 => datetime_now());


    return $job->retry({delay => $DELAY});
}

1;
