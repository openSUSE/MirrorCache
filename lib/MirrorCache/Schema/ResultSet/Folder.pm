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

sub get_db_sync_queue_position {
    my ($self, $path) = @_;
    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = <<'END_SQL';
select 1+count(*) as cnt
from folder f
where f.db_sync_scheduled > (select db_sync_scheduled from folder f1 where path = ?)
and f.db_sync_priority >= (select db_sync_priority from folder f1 where path = ?)
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute($path, $path);
    return $dbh->selectrow_array($prep);
}

sub request_db_sync {
    my ($self, $path, $priority) = @_;
    $priority = 10 unless $priority;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = <<'END_SQL';
insert into folder(path, db_sync_scheduled, db_sync_priority)
values (?, now(), ?)
on conflict(path) do update set
db_sync_scheduled = CASE WHEN folder.db_sync_scheduled > folder.db_sync_last THEN folder.db_sync_scheduled ELSE now() END,
db_sync_priority = ?
returning id
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute($path, $priority, $priority);
    my $res = $prep->fetchrow_arrayref;
    return $res->[0];
}

sub request_for_country {
    my ($self, $folder_id, $country) = @_;
    return undef unless $country;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $seconds = int($ENV{'MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT'} // 120);

    my $sql = <<'END_SQL';
insert into demand as d(folder_id, country, last_request)
values (?, ?, now())
on conflict(folder_id, country) do update set
last_request = now()
where ( ? = 0 ) OR
( 0 = date_part('day',    d.last_request - excluded.last_request) and
0 = date_part('hour',   d.last_request - excluded.last_request) and
? > date_part('second', d.last_request - excluded.last_request) )
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute($folder_id, $country, $seconds, $seconds);
}

sub scan_complete {
    my ($self, $folder_id, $country, $mirror_count) = @_;
    return undef unless $country;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $seconds = int($ENV{'MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT'} // 120);

    my $sql = 'update demand set last_scan = now(), mirror_count_country = ? where folder_id = ? and country = ?';
    my $prep = $dbh->prepare($sql);
    $prep->execute($mirror_count, $folder_id, $country);
}

sub request_for_mirrorlist {
    my ($self, $folder_id) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $seconds = int($ENV{'MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT'} // 120);

    my $sql = <<'END_SQL';
insert into demand_mirrorlist as d(folder_id, last_request)
values (?, now())
on conflict(folder_id) do update set
last_request = now()
where ( ? = 0 ) OR
( 0 = date_part('day',    d.last_request - excluded.last_request) and
0 = date_part('hour',   d.last_request - excluded.last_request) and
? > date_part('second', d.last_request - excluded.last_request) )
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute($folder_id, $seconds, $seconds);
}

sub scan_region_complete {
    my ($self, $folder_id, $region, $mirror_count) = @_;
    return undef unless $region;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $seconds = int($ENV{'MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT'} // 120);

    my $sql = 'update demand_region set last_scan = now(), mirror_count = ? where folder_id = ? and region = ?';
    my $prep = $dbh->prepare($sql);
    $prep->execute($mirror_count, $folder_id, $region);
}

sub find_folder_or_redirect {
    my ($self, $path) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = <<'END_SQL';
select id, db_sync_last, '' as pathto
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

    my $sql = <<'END_SQL';
select s.hostname, fds.dt, count(distinct file_id) as missing_files, (select name from file where id = max(file_id)) as missing_file
from server s
join folder_diff_server fds on s.id = fds.server_id
join folder_diff fd on fd.id = fds.folder_diff_id
join folder f on f.id = fd.folder_id and f.path = ?
left join folder_diff_file fdf on fdf.folder_diff_id = fd.id
left join file fl on fl.id = fdf.file_id
where (
select max(file.dt) from file where folder_id = f.id and not (name like '%/')) <= fds.dt
and (fdf.file_id is null or fl.name is not null) -- ignore deleted files
and (fl.name is NULL or not (fl.name like '%/')) -- ignore folders
group by s.id, fds.dt;
END_SQL

    return $dbh->selectall_hashref($sql, 'hostname', {}, $path);
}

sub stats_outdated {
    my ($self, $path) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = <<'END_SQL';
select s.hostname, fds.dt, count(distinct file_id) as missing_files
from server s
join folder_diff_server fds on s.id = fds.server_id
join folder_diff fd on fd.id = fds.folder_diff_id
join folder f on f.id = fd.folder_id and f.path = ?
left join folder_diff_file fdf on fdf.folder_diff_id = fd.id
left join file fl on fl.id = fdf.file_id
where (
select max(file.dt) from file where folder_id = f.id and not (name like '%/')) > fds.dt
and (fdf.file_id is null or fl.name is not null) -- ignore deleted files
and (fl.name is NULL or not (fl.name like '%/')) -- ignore folders
group by s.id, fds.dt;
END_SQL

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
select f.id as id, db_sync_last as last_sync,
sum(case when (select max(dt) dt from file where folder_id = f.id and not (name like '%/')) <= fds.dt then 1 else 0 end ) as recent,
sum(case when (select max(dt) dt from file where folder_id = f.id and not (name like '%/')) > fds.dt then 1 else 0 end ) as outdated,
sum(case when fds.dt is null then 1 else 0 end ) as not_scanned,
case when db_sync_scheduled > db_sync_last then (select 1+count(*)
      from folder f1
      where f1.db_sync_scheduled > f1.db_sync_last
      and f1.id <> f.id
      and ((f1.db_sync_scheduled < f.db_sync_scheduled and f1.db_sync_priority = f.db_sync_priority) or (f1.db_sync_priority > f.db_sync_priority))
) else NULL end as sync_job_position
from server s
left join folder_diff_server fds on fds.server_id = s.id
left join folder_diff fd on fd.id = fds.folder_diff_id
left join folder f on fd.folder_id = f.id
where f.path = ?
group by f.id, f.db_sync_last;
END_SQL

    my $prep = $dbh->prepare($sql);
    $prep->execute($path);
    return $dbh->selectrow_hashref($prep);
}

sub delete_cascade {
    my ($self, $id, $only_diff) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    $schema->txn_do(
        sub {
            $dbh->prepare("DELETE FROM folder_diff_server
    USING folder_diff
    WHERE folder_diff_id = folder_diff.id
        AND folder_id = ?")->execute($id);

            $dbh->prepare("DELETE FROM folder_diff_file
    USING folder_diff
    WHERE folder_diff_id = folder_diff.id
        AND folder_id = ?")->execute($id);

            $dbh->prepare("DELETE FROM folder_diff WHERE folder_id = ?")->execute($id);

            $dbh->prepare("DELETE FROM file WHERE folder_id = ?")->execute($id) unless $only_diff;
            $dbh->prepare("DELETE FROM folder WHERE id = ?")->execute($id) unless $only_diff;
        });
}

sub delete_diff {
    my ($self, $id) = @_;
    $self->delete_cascade($id, 1);
}

1;
