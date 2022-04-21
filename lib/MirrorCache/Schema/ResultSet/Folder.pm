# Copyright (C) 2020 SUSE LLC
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

package MirrorCache::Schema::ResultSet::Folder;

use strict;
use warnings;

use base 'DBIx::Class::ResultSet';

sub get_sync_queue_position {
    my ($self, $path) = @_;
    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = <<'END_SQL';
select 1+count(*) as cnt
from folder f
where f.sync_requested < (select sync_requested from folder f1 where path = ?) and f.sync_requested > f.sync_scheduled
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute($path);
    return $dbh->selectrow_array($prep);
}

sub set_wanted {
    my ($self, $folder_id) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql;
if ($dbh->{Driver}->{Name} eq 'Pg') {
    $sql = << "END_SQL";
update folder
set wanted = now()
where id = ? and (wanted < now() -  2*7*24*60* interval '60 second' or wanted is null)
END_SQL
} else {
    $sql = << "END_SQL";
update folder
set wanted = CURRENT_TIMESTAMP(3)
where id = ? and (wanted < date_sub(CURRENT_TIMESTAMP(3), interval 2*7*24*60 minute) or wanted is null)
END_SQL
}
    my $prep = $dbh->prepare($sql);
    $prep->execute($folder_id);
}

sub request_sync {
    my ($self, $path) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql;
if ($dbh->{Driver}->{Name} eq 'Pg') {
    $sql = <<'END_SQL';
insert into folder(path, wanted, sync_requested)
values (?, now(), now())
on conflict(path) do update set
sync_requested = CASE WHEN folder.sync_requested > folder.sync_scheduled THEN folder.sync_requested ELSE now() END,
wanted = CASE WHEN folder.wanted < now() - interval '24 hour' THEN now() ELSE folder.wanted END
returning id
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute($path);
    my $res = $prep->fetchrow_arrayref;
    return $res->[0];
}
    $sql = <<'END_SQL';
insert into folder(path, wanted, sync_requested)
values (?, CURRENT_TIMESTAMP(3), CURRENT_TIMESTAMP(3))
on duplicate key update
sync_requested = if(sync_requested > sync_scheduled, sync_requested, CURRENT_TIMESTAMP(3)),
wanted = if(wanted < adddate(CURRENT_TIMESTAMP(3), -1), CURRENT_TIMESTAMP(3), wanted)
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute($path);

    $prep = $dbh->prepare('select id from folder where path = ?');
    $prep->execute($path);

    my $res = $prep->fetchrow_arrayref;
    return $res->[0];
}

sub request_sync_array {
    my $self = shift;
    my @ids = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = <<'END_SQL';
update folder set sync_requested = CURRENT_TIMESTAMP(3)
where ( sync_requested <= COALESCE(sync_scheduled, sync_last, CURRENT_TIMESTAMP(3)) or sync_requested is null )
END_SQL
    $sql = $sql . " AND id in (" . join( ',', map { '?' } @ids ) . ')';
    my $prep = $dbh->prepare($sql);
    $prep->execute(@ids);
}


sub request_scan {
    my ($self, $folder_id) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = << "END_SQL";
update folder
set scan_requested = CURRENT_TIMESTAMP(3)
where id = ? and (scan_requested IS NULL or scan_scheduled IS NULL or scan_requested <= scan_scheduled)
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute($folder_id);
}

sub request_scan_array {
    my $self = shift;
    my @ids = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = <<'END_SQL';
update folder set scan_requested = CURRENT_TIMESTAMP(3)
where ( scan_requested < COALESCE(scan_scheduled, scan_last, CURRENT_TIMESTAMP(3)) or scan_requested is null )
END_SQL
    $sql = $sql . " AND id in (" . join( ',', map { '?' } @ids ) . ')';
    my $prep = $dbh->prepare($sql);
    $prep->execute(@ids);
}

sub scan_complete {
    my ($self, $folder_id) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = 'update folder set scan_last = CURRENT_TIMESTAMP(3), scan_scheduled = coalesce(scan_scheduled, CURRENT_TIMESTAMP(3)) where id = ?';
    my $prep = $dbh->prepare($sql);
    $prep->execute($folder_id);
}

sub find_folder_or_redirect {
    my ($self, $path) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = <<'END_SQL';
select id, sync_last, '' as pathto
from folder
where path = ?
union
select id, NULL, pathto
from redirect
where pathfrom = ?
limit 1
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute($path, $path);
    return $dbh->selectrow_hashref($prep);
}

sub stats_recent {
    my ($self, $path) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql;
if ($dbh->{Driver}->{Name} eq 'Pg') {
    $sql = <<'END_SQL';
select s.hostname, fds.dt, count(distinct file_id) as missing_files, (select name from file where id = max(file_id)) as missing_file
from server s
join folder_diff_server fds on s.id = fds.server_id
join folder_diff fd on fd.id = fds.folder_diff_id
join folder f on f.id = fd.folder_id and f.path = ?
left join folder_diff_file fdf on fdf.folder_diff_id = fd.id
left join file fl on fl.id = fdf.file_id
where (
select date_trunc('second', max(file.dt)) from file where folder_id = f.id and not (name like '%/')) <= date_trunc('second', fds.dt)
and (fdf.file_id is null or fl.name is not null) -- ignore deleted files
and (fl.name is NULL or not (fl.name like '%/')) -- ignore folders
group by s.id, fds.dt;
END_SQL
} else {
    $sql = <<'END_SQL';
select s.hostname, fds.dt, count(distinct file_id) as missing_files, (select name from file where id = max(file_id)) as missing_file
from server s
join folder_diff_server fds on s.id = fds.server_id
join folder_diff fd on fd.id = fds.folder_diff_id
join folder f on f.id = fd.folder_id and f.path = ?
left join folder_diff_file fdf on fdf.folder_diff_id = fd.id
left join file fl on fl.id = fdf.file_id
where (
select cast(max(file.dt) as datetime) from file where folder_id = f.id and not (name like '%/')) <= cast(fds.dt as datetime)
and (fdf.file_id is null or fl.name is not null) -- ignore deleted files
and (fl.name is NULL or not (fl.name like '%/')) -- ignore folders
group by s.id, fds.dt;
END_SQL
}

    return $dbh->selectall_hashref($sql, 'hostname', {}, $path);
}

sub stats_outdated {
    my ($self, $path) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql;
if ($dbh->{Driver}->{Name} eq 'Pg') {
    $sql = <<'END_SQL';
select s.hostname, fds.dt, count(distinct file_id) as missing_files
from server s
join folder_diff_server fds on s.id = fds.server_id
join folder_diff fd on fd.id = fds.folder_diff_id
join folder f on f.id = fd.folder_id and f.path = ?
left join folder_diff_file fdf on fdf.folder_diff_id = fd.id
left join file fl on fl.id = fdf.file_id
where (
select date_trunc('second', max(file.dt)) from file where folder_id = f.id and not (name like '%/')) > date_trunc('second', fds.dt)
and (fdf.file_id is null or fl.name is not null) -- ignore deleted files
and (fl.name is NULL or not (fl.name like '%/')) -- ignore folders
group by s.id, fds.dt;
END_SQL
} else {
    $sql = <<'END_SQL';
select s.hostname, fds.dt, count(distinct file_id) as missing_files
from server s
join folder_diff_server fds on s.id = fds.server_id
join folder_diff fd on fd.id = fds.folder_diff_id
join folder f on f.id = fd.folder_id and f.path = ?
left join folder_diff_file fdf on fdf.folder_diff_id = fd.id
left join file fl on fl.id = fdf.file_id
where (
select cast(max(file.dt) as datetime) from file where folder_id = f.id and not (name like '%/')) > cast(fds.dt as datetime)
and (fdf.file_id is null or fl.name is not null) -- ignore deleted files
and (fl.name is NULL or not (fl.name like '%/')) -- ignore folders
group by s.id, fds.dt;
END_SQL
}
    return $dbh->selectall_hashref($sql, 'hostname', {}, $path);
}

sub stats_not_scanned {
    my ($self, $path) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = <<'END_SQL';
select s.hostname
    from server s
    left join ( select fds.server_id as server_id from
    folder f join folder_diff fd on fd.folder_id = f.id
    join folder_diff_server fds on fd.id = fds.folder_diff_id
    where f.path = ? ) x
    on x.server_id = s.id
    where x.server_id is NULL
END_SQL

    return $dbh->selectall_hashref($sql, 'hostname', {}, $path);
}

sub stats_all {
    my ($self, $path) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = <<'END_SQL';
select f.id as id, sync_last as last_sync,
sum(case when (select date_trunc('second', max(dt)) dt from file where folder_id = f.id and not (name like '%/')) <= date_trunc('second', fds.dt) then 1 else 0 end ) as recent,
sum(case when (select date_trunc('second', max(dt)) dt from file where folder_id = f.id and not (name like '%/')) > date_trunc('second', fds.dt) then 1 else 0 end ) as outdated,
sum(case when fds.dt is null then 1 else 0 end ) as not_scanned,
case when sync_scheduled > sync_last then (select 1+count(*)
      from folder f1
      where f1.sync_scheduled > f1.sync_last
      and f1.id <> f.id
      and (f1.sync_scheduled < f.sync_scheduled)
) else NULL end as sync_job_position
from server s
left join folder_diff_server fds on fds.server_id = s.id
left join folder_diff fd on fd.id = fds.folder_diff_id
left join folder f on fd.folder_id = f.id
where f.path = ?
group by f.id, f.sync_last;
END_SQL
    $sql =~ s/date_trunc\('second', max\(dt\)\)/convert(max(dt), DATETIME)/g unless $dbh->{Driver}->{Name} eq 'Pg';
    $sql =~ s/date_trunc\('second', fds.dt\)/cast(fds.dt as datetime)/g unless $dbh->{Driver}->{Name} eq 'Pg';

    my $prep = $dbh->prepare($sql);
    $prep->execute($path);
    return $dbh->selectrow_hashref($prep);
}

sub delete_cascade {
    my ($self, $id, $only_diff) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql1 = "DELETE FROM folder_diff_server
    USING folder_diff
    WHERE folder_diff_id = folder_diff.id
        AND folder_id = ?";

    $sql1 = "DELETE fdf FROM folder_diff_server fdf
    JOIN folder_diff
    ON fdf.folder_diff_id = folder_diff.id
        AND folder_id = ?" unless $dbh->{Driver}->{Name} eq 'Pg';


    my $sql2 = "DELETE FROM folder_diff_file
    USING folder_diff
    WHERE folder_diff_id = folder_diff.id
        AND folder_id = ?";

    $sql2 = "DELETE fdf FROM folder_diff_file fdf
    JOIN folder_diff
    WHERE folder_diff_id = folder_diff.id
        AND folder_id = ?" unless $dbh->{Driver}->{Name} eq 'Pg';

    eval {
    $schema->txn_do(
        sub {
            $dbh->prepare($sql1)->execute($id);

            $dbh->prepare($sql2)->execute($id);

            $dbh->prepare("DELETE FROM folder_diff WHERE folder_id = ?")->execute($id);

            $dbh->prepare("DELETE FROM file WHERE folder_id = ?")->execute($id) unless $only_diff;
            $dbh->prepare("DELETE FROM folder WHERE id = ?")->execute($id) unless $only_diff;
        });
        1;
    } or do {
        die $@;
    };
}

sub delete_diff {
    my ($self, $id) = @_;
    $self->delete_cascade($id, 1);
}

1;
