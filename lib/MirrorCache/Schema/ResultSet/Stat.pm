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

package MirrorCache::Schema::ResultSet::Stat;

use strict;
use warnings;

use base 'DBIx::Class::ResultSet';
use Mojo::File qw(path);


sub prev_minute {
    shift->_prev_period('minute');
}

sub prev_hour {
    shift->_prev_period('hour');
}

sub prev_day {
    shift->_prev_period('day');
}

my $BOT_MASK = $ENV{MIRRORCACHE_BOT_MASK} // '.*(bot|rclone).*';

my $SQLCURR_PG = <<"END_SQL";
select
sum(case when mirror_id >= 0 and dt > date_trunc('minute', CURRENT_TIMESTAMP(3)) and not (lower(agent) ~ '$BOT_MASK') then 1 else 0 end) as hit_minute,
sum(case when mirror_id = -1 and dt > date_trunc('minute', CURRENT_TIMESTAMP(3)) and not (lower(agent) ~ '$BOT_MASK') then 1 else 0 end) as miss_minute,
sum(case when mirror_id < -1 and dt > date_trunc('minute', CURRENT_TIMESTAMP(3)) and not (lower(agent) ~ '$BOT_MASK') then 1 else 0 end) as geo_minute,
sum(case when                    dt > date_trunc('minute', CURRENT_TIMESTAMP(3)) and      lower(agent) ~ '$BOT_MASK'  then 1 else 0 end) as bot_minute,
sum(case when mirror_id >= 0 and dt > date_trunc('hour', CURRENT_TIMESTAMP(3))   and not (lower(agent) ~ '$BOT_MASK') then 1 else 0 end) as hit_hour,
sum(case when mirror_id = -1 and dt > date_trunc('hour', CURRENT_TIMESTAMP(3))   and not (lower(agent) ~ '$BOT_MASK') then 1 else 0 end) as miss_hour,
sum(case when mirror_id < -1 and dt > date_trunc('hour', CURRENT_TIMESTAMP(3))   and not (lower(agent) ~ '$BOT_MASK') then 1 else 0 end) as geo_hour,
sum(case when                    dt > date_trunc('hour', CURRENT_TIMESTAMP(3))   and      lower(agent) ~ '$BOT_MASK'  then 1 else 0 end) as bot_hour,
sum(case when mirror_id >= 0                                                     and not (lower(agent) ~ '$BOT_MASK') then 1 else 0 end) as hit_day,
sum(case when mirror_id = -1                                                     and not (lower(agent) ~ '$BOT_MASK') then 1 else 0 end) as miss_day,
sum(case when mirror_id < -1                                                     and not (lower(agent) ~ '$BOT_MASK') then 1 else 0 end) as geo_day,
sum(case when                                                                             lower(agent) ~ '$BOT_MASK'  then 1 else 0 end) as bot_day
from stat
where dt > date_trunc('day', CURRENT_TIMESTAMP(3))
END_SQL


# it is too expensive to aggregate over stat for whole day, so we try add hour stats from stat_agg (pg might use the same optimization as well)
my $SQLCURR_MARIADB = <<"END_SQL";
select
hit_minute,
miss_minute,
geo_minute,
bot_minute,
hit_hour,
miss_hour,
geo_hour,
bot_hour,
agg_hour.hit_day  + coalesce(hit,0)  as hit_day,
agg_hour.miss_day + coalesce(miss,0) as miss_day,
agg_hour.geo_day  + coalesce(geo,0)  as geo_day,
agg_hour.bot_day  + coalesce(bot,0)  as bot_day
from
(
select
sum(case when mirror_id >= 0  and dt > date_sub(CURRENT_TIMESTAMP(3), interval 1 minute) and not (lower(agent) regexp '$BOT_MASK') then 1 else 0 end) as hit_minute,
sum(case when mirror_id = -1  and dt > date_sub(CURRENT_TIMESTAMP(3), interval 1 minute) and not (lower(agent) regexp '$BOT_MASK') then 1 else 0 end) as miss_minute,
sum(case when mirror_id < -1  and dt > date_sub(CURRENT_TIMESTAMP(3), interval 1 minute) and not (lower(agent) regexp '$BOT_MASK') then 1 else 0 end) as geo_minute,
sum(case when                     dt > date_sub(CURRENT_TIMESTAMP(3), interval 1 minute) and     (lower(agent) regexp '$BOT_MASK') then 1 else 0 end) as bot_minute,
sum(case when mirror_id >= 0  and dt > date_sub(CURRENT_TIMESTAMP(3), interval 1 hour)   and not (lower(agent) regexp '$BOT_MASK') then 1 else 0 end) as hit_hour,
sum(case when mirror_id = -1  and dt > date_sub(CURRENT_TIMESTAMP(3), interval 1 hour)   and not (lower(agent) regexp '$BOT_MASK') then 1 else 0 end) as miss_hour,
sum(case when mirror_id < -1  and dt > date_sub(CURRENT_TIMESTAMP(3), interval 1 hour)   and not (lower(agent) regexp '$BOT_MASK') then 1 else 0 end) as geo_hour,
sum(case when                     dt > date_sub(CURRENT_TIMESTAMP(3), interval 1 hour)   and     (lower(agent) regexp '$BOT_MASK') then 1 else 0 end) as bot_hour,
sum(case when mirror_id >= 0                                                             and not (lower(agent) regexp '$BOT_MASK') then 1 else 0 end) as hit_day,
sum(case when mirror_id = -1                                                             and not (lower(agent) regexp '$BOT_MASK') then 1 else 0 end) as miss_day,
sum(case when mirror_id < -1                                                             and not (lower(agent) regexp '$BOT_MASK') then 1 else 0 end) as geo_day,
sum(case when                                                                                    (lower(agent) regexp '$BOT_MASK') then 1 else 0 end) as bot_day
from (
select lastdt from (select dt as lastdt from stat_agg where period = 'hour' order by dt desc limit 1) x union select date_sub(CURRENT_TIMESTAMP(3), interval 1 hour) limit 1
) lastagg join stat on dt > lastdt
) agg_hour
left join
(
select
sum(case when mirror_id >= 0 then hit_count else 0 end) as hit,
sum(case when mirror_id = -1 then hit_count else 0 end) as miss,
sum(case when mirror_id < -1 and mirror_id != -100 then hit_count else 0 end) as geo,
sum(case when mirror_id = -100 then hit_count else 0 end) as bot
from stat_agg
where
period = 'hour'
and dt <= (select dt from stat_agg where period = 'hour' order by dt desc limit 1)
and dt > date_sub(CURRENT_TIMESTAMP(3), interval 1 day)
) agg_day on 1=1
END_SQL


sub curr {
    my ($self) = @_;
    my $dbh = $self->result_source->schema->storage->dbh;

    my $sql;
    if ($dbh->{Driver}->{Name} eq 'Pg') {
        $sql = $SQLCURR_PG;
    } else {
        $sql = $SQLCURR_MARIADB;
    }
    my $prep = $dbh->prepare($sql);
    $prep->execute();
    return $dbh->selectrow_hashref($prep);
}

sub _prev_period {
    my ($self, $period) = @_;
    my $dbh     = $self->result_source->schema->storage->dbh;

    my $sql = <<"END_SQL";
select
sum(case when mirror_id >= 0 then hit_count else 0 end) as hit,
sum(case when mirror_id = -1 then hit_count else 0 end) as miss,
sum(case when mirror_id < -1 and mirror_id != -100 then hit_count else 0 end) as geo,
sum(case when mirror_id = -100 then hit_count else 0 end) as bot
from stat_agg
where period = '$period'::stat_period_t and dt = (select dt from stat_agg where period = '$period'::stat_period_t order by dt desc limit 1)
group by dt;
END_SQL
    $sql =~ s/::stat_period_t//g unless $dbh->{Driver}->{Name} eq 'Pg';

    my $prep = $dbh->prepare($sql);
    $prep->execute();
    return $dbh->selectrow_hashref($prep);
}

sub latest_hit {
    my ($self, $prev_stat_id) = @_;
    $prev_stat_id = 0 unless $prev_stat_id;
    my $dbh     = $self->result_source->schema->storage->dbh;

    my $sql = << "END_SQL";
select stat.id, mirror_id, trim(stat.country),
       concat(case when secure then 'https://' else 'http://' end, CASE WHEN length(server.hostname_vpn)>0 THEN server.hostname_vpn ELSE server.hostname END, server.urldir, case when metalink then regexp_replace(path, '(.*)\.(metalink|meta4)', E'\\1') else path end) as url,
       regexp_replace(path, '(^.*)/[^/]*', E'\\1') as folder, folder_id
       from stat join server on mirror_id = server.id
       where stat.id > $prev_stat_id
       order by stat.id desc
       limit 1
END_SQL
    $sql =~ s/E'/'/g unless $dbh->{Driver}->{Name} eq 'Pg';
    $sql =~ s/join server/straight_join server/g unless $dbh->{Driver}->{Name} eq 'Pg';

    my $prep = $dbh->prepare($sql);
    local $SIG{ALRM} = sub { die "TIMEOUT in latest_hit\n" };
    alarm(10);
    $prep->execute();
    alarm(0);
    return $dbh->selectrow_array($prep);
};

# this should return recent requests for unknown yet files or folders
sub path_misses {
    my ($self, $prev_stat_id, $limit) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = << 'END_SQL';
select * from (
select stat.id, stat.path, stat.folder_id, trim(country)
from stat left join folder on folder.id = stat.folder_id
where
(
	(( mirror_id in (0,-1) or mirrorlist ) and ( file_id is null )) -- unknown file
or
	( folder_id is null and mirror_id > -2 ) -- file may be known, but requested folder is unknown - happens when realpath shows to a different folder
)
and stat.path !~ '\/(repodata\/repomd\.xml[^\/]*|media\.1\/(media|products)|content|.*\.sha\d\d\d(\.asc)?|Release(\.key|\.gpg)?|InRelease|Packages(\.gz|\.zst)?|Sources(\.gz|\.zst)?|.*_Arch\.(files|db|key)(\.(sig|tar\.gz(\.sig)?|tar\.zst(\.sig)?))?|(files|primary|other)\.xml\.(gz|zck|zst)|[Pp]ackages(\.[A-Z][A-Z])?\.(xz|gz|zst)|gpg-pubkey.*\.asc|CHECKSUMS(\.asc)?|APKINDEX\.tar\.gz)$'
and lower(stat.agent) NOT LIKE '%bot%'
and lower(stat.agent) NOT LIKE '%rclone%'
and (
    stat.folder_id is null or
    folder.sync_requested < folder.sync_scheduled
    )
END_SQL
    $sql = "$sql and stat.id > $prev_stat_id" if $prev_stat_id;
    $limit = $limit + 1;
    $sql = "$sql limit $limit";
    $sql = "$sql ) x";
    $sql = "$sql union all select max(id), '-max_id', null, null from stat"; # this is just to get max(id) in the same query
    $sql = "$sql order by id desc";

    $sql =~ s/\!\~/not regexp/g unless $dbh->{Driver}->{Name} eq 'Pg';

    my $prep = $dbh->prepare($sql);
    $prep->execute();
    my $arrayref = $dbh->selectall_arrayref($prep, { Slice => {} });
    my $id;
    my %folders = ();
    my %countries = ();
    foreach my $miss ( @$arrayref ) {
        $id = $miss->{id} unless $id;
        my $path = $miss->{path};
        next unless $path;
        next if $path eq '-max_id';
        $path = path($path)->dirname;
        $folders{$path} = 1;
        my $country = $miss->{country};
        $countries{$country} = 1 if $country;
    }
    my @country_list = (sort keys %countries);
    my @folders = (sort keys %folders);
    return ($id, \@folders, \@country_list);
}


# this should return recent requests for unknown yet files or folders
sub path_misses_shard {
    my ($self, $min_stat_id, $max_stat_id, $shard) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = << 'END_SQL';
select stat.id, stat.path, stat.folder_id, trim(country)
from stat left join folder on folder.id = stat.folder_id
where
(
	(( mirror_id in (0,-1) or mirrorlist ) and ( file_id is null )) -- unknown file
or
	( folder_id is null and mirror_id > -2 ) -- file may be known, but requested folder is unknown - happens when realpath shows to a different folder
)
and stat.path !~ '\/(repodata\/repomd\.xml[^\/]*|media\.1\/(media|products)|content|.*\.sha\d\d\d(\.asc)?|Release(\.key|\.gpg)?|InRelease|Packages(\.gz|\.zst)?|Sources(\.gz|\.zst)?|.*_Arch\.(files|db|key)(\.(sig|tar\.gz(\.sig)?|tar\.zst(\.sig)?))?|(files|primary|other)\.xml\.(gz|zck|zst)|[Pp]ackages(\.[A-Z][A-Z])?\.(xz|gz|zst)|gpg-pubkey.*\.asc|CHECKSUMS(\.asc)?|APKINDEX\.tar\.gz)$'
and lower(stat.agent) NOT LIKE '%bot%'
and lower(stat.agent) NOT LIKE '%rclone%'
and stat.id between ? and ?
and stat.path like ?
and (
    stat.folder_id is null or
    folder.sync_requested < folder.sync_scheduled
    )
END_SQL

    $sql =~ s/\!\~/not regexp/g unless $dbh->{Driver}->{Name} eq 'Pg';

    my $prep = $dbh->prepare($sql);
    $prep->execute($min_stat_id, $max_stat_id, "/$shard");
    my $arrayref = $dbh->selectall_arrayref($prep, { Slice => {} });
    my $id;
    my %folders = ();
    foreach my $miss ( @$arrayref ) {
        my $path = $miss->{path};
        next unless $path;
        $path = path($path)->dirname;
        $folders{$path} = 1;
    }
    my @folders = (sort keys %folders);
    return (\@folders);
}

sub mirror_misses {
    my ($self, $prev_stat_id, $limit) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;
    my $limit1  = ($limit // 1) + 1;

    my $sql = << "END_SQL";
select * from (
select stat.id, stat.folder_id, trim(country)
from stat join folder on folder.id = stat.folder_id
where mirror_id in (-1, 0) and file_id is not null
and lower(stat.agent) NOT LIKE '%bot%'
and lower(stat.agent) NOT LIKE '%rclone%'
and (
    folder.id is null or
    folder.scan_last is null or folder.scan_last > folder.scan_scheduled
    )
END_SQL
    $sql = "$sql and stat.id > $prev_stat_id" if $prev_stat_id;
    $sql = "$sql order by stat.id desc limit $limit1 ) x";
    $sql = "$sql union all select max(id), 0, null from stat"; # this is just to get max(id) in the same query
    $sql = "$sql order by id desc";

    my $prep = $dbh->prepare($sql);
    $prep->execute();
    my $arrayref = $dbh->selectall_arrayref($prep, { Slice => {} });
    my $id;
    my %folder_ids = ();
    my %countries = ();
    foreach my $miss ( @$arrayref ) {
        $id = $miss->{id} unless $id;
        my $folder_id = $miss->{folder_id};
        next unless $folder_id;
        $folder_ids{$folder_id} = 1;
        my $country = $miss->{country};
        $countries{$country} = 1 if $country;
    }
    my @country_list = (sort keys %countries);
    my @folder_ids = (sort keys %folder_ids);
    return ($id, \@folder_ids, \@country_list);
}

sub secure_max_id {
    my ($self, $prev_stat_id) = @_;
    my $max_id = $self->get_column("id")->max;

    return 0 unless $max_id;

    $prev_stat_id = $max_id - 100000 if !$prev_stat_id || $max_id - $prev_stat_id > 10000 || $prev_stat_id > $max_id;
    $prev_stat_id = 0 if $prev_stat_id < 0;
    return $prev_stat_id;
}


my $SQLEFFICIENCY_HOURLY_PG = <<"END_SQL";
select
extract(epoch from now())::integer as dt,
hit_minute  + coalesce(hit,0)  as hit,
miss_minute + coalesce(miss,0) as miss,
pass_minute + coalesce(pass,0) as pass,
geo_minute  + coalesce(geo,0)  as geo,
bot_minute  + coalesce(bot,0)  as bot
from
(
select
sum(case when mirror_id >  0 and not (lower(agent) ~ '$BOT_MASK') then 1 else 0 end) as hit_minute,
sum(case when mirror_id = -1 and not (lower(agent) ~ '$BOT_MASK') then 1 else 0 end) as miss_minute,
sum(case when mirror_id = 0  and not (lower(agent) ~ '$BOT_MASK') then 1 else 0 end) as pass_minute,
sum(case when mirror_id < -1 and not (lower(agent) ~ '$BOT_MASK') then 1 else 0 end) as geo_minute,
sum(case when                        (lower(agent) ~ '$BOT_MASK') then 1 else 0 end) as bot_minute
from (
select lastdt from (select dt as lastdt from stat_agg where period = 'minute' order by dt desc limit 1) x union select CURRENT_TIMESTAMP(3) - interval '1 hour' limit 1
) lastagg join stat on dt > lastdt
) agg_minute
left join
(
select
sum(case when mirror_id >  0 then hit_count else 0 end) as hit,
sum(case when mirror_id = -1 then hit_count else 0 end) as miss,
sum(case when mirror_id = 0  then hit_count else 0 end) as pass,
sum(case when mirror_id < -1 and mirror_id != -100 then hit_count else 0 end) as geo,
sum(case when mirror_id = -100 then hit_count else 0 end) as bot
from stat_agg
where
period = 'minute'
and dt <= (select dt from stat_agg where period = 'minute' order by dt desc limit 1)
and dt > date_trunc('hour', CURRENT_TIMESTAMP(3))
) agg_hour on 1=1
union
select extract(epoch from dt)::integer,
sum(case when mirror_id > 0  then hit_count else 0 end) as hit,
sum(case when mirror_id = -1 then hit_count else 0 end) as miss,
sum(case when mirror_id = 0  then hit_count else 0 end) as pass,
sum(case when mirror_id < -1 and mirror_id != -100 then hit_count else 0 end) as geo,
sum(case when mirror_id = -100 then hit_count else 0 end) as bot
from stat_agg
where
period = 'hour'
and dt <= date_trunc('hour', CURRENT_TIMESTAMP(3)) and dt > CURRENT_TIMESTAMP(3) - interval '30 hour'
group by dt
order by 1 desc
limit 30
END_SQL



my $SQLEFFICIENCY_DAILY_PG = <<"END_SQL";
select
extract(epoch from now())::integer as dt,
sum(hit)  as hit,
sum(miss) as miss,
sum(pass) as pass,
sum(geo)  as geo,
sum(bot)  as bot
from
(
select
sum(case when mirror_id >  0  and not (lower(agent) ~ '$BOT_MASK') then 1 else 0 end) as hit,
sum(case when mirror_id = -1  and not (lower(agent) ~ '$BOT_MASK') then 1 else 0 end) as miss,
sum(case when mirror_id = 0   and not (lower(agent) ~ '$BOT_MASK') then 1 else 0 end) as pass,
sum(case when mirror_id < -1  and not (lower(agent) ~ '$BOT_MASK') then 1 else 0 end) as geo,
sum(case when                         (lower(agent) ~ '$BOT_MASK') then 1 else 0 end) as bot
from (
select lastdt from (select dt as lastdt from stat_agg where period = 'hour' order by dt desc limit 1) x union select date_trunc('day', CURRENT_TIMESTAMP(3)) limit 1
) lastagg join stat on dt > lastdt
union
select
sum(case when mirror_id >  0 then hit_count else 0 end) as hit,
sum(case when mirror_id = -1 then hit_count else 0 end) as miss,
sum(case when mirror_id = 0  then hit_count else 0 end) as pass,
sum(case when mirror_id < -1 and mirror_id != -100 then hit_count else 0 end) as geo,
sum(case when mirror_id = -100 then hit_count else 0 end) as bot
from stat_agg
where
period = 'hour'
and dt <= (select dt from stat_agg where period = 'hour' order by dt desc limit 1)
and dt > date_trunc('day', CURRENT_TIMESTAMP(3))
group by dt
) heute
union
select extract(epoch from dt)::integer,
sum(case when mirror_id > 0  then hit_count else 0 end) as hit,
sum(case when mirror_id = -1 then hit_count else 0 end) as miss,
sum(case when mirror_id = 0  then hit_count else 0 end) as pass,
sum(case when mirror_id < -1 and mirror_id != -100 then hit_count else 0 end) as geo,
sum(case when mirror_id = -100 then hit_count else 0 end) as bot
from stat_agg
where
period = 'day'
and dt <= date_trunc('day', CURRENT_TIMESTAMP(3)) and dt > CURRENT_TIMESTAMP(3) - 30 * 24 * interval '1 hour'
group by dt
order by 1 desc
limit 30
END_SQL


sub select_efficiency() {
    my ($self, $period, $limit) = @_;

    my $sql;
    my $dbh = $self->result_source->schema->storage->dbh;

    $sql = $SQLEFFICIENCY_HOURLY_PG;
    $sql = $SQLEFFICIENCY_DAILY_PG if $period eq 'day';

    if ($dbh->{Driver}->{Name} ne 'Pg') {
        $sql =~ s/date_trunc\('day', CURRENT_TIMESTAMP\(3\)\)/date(CURRENT_TIMESTAMP(3))/g;
        $sql =~ s/date_trunc\('hour', CURRENT_TIMESTAMP\(3\)\)/CURDATE() + INTERVAL hour(now()) HOUR/g;
        $sql =~ s/ ~ / REGEXP /g;
        $sql =~ s/30 \* 24 \* interval '1 hour'/interval 30 day/g;
        $sql =~ s/interval 'hour'/interval 1 hour/g;
        $sql =~ s/interval '1 hour'/interval 1 hour/g;
        $sql =~ s/interval '30 hour'/interval 30 hour/g;
        $sql =~ s/interval 'day'/interval 1 day/g;
        $sql =~ s/extract\(epoch from now\(\)\)::integer/floor(unix_timestamp(now()))/g;
        $sql =~ s/extract\(epoch from dt\)::integer/floor(unix_timestamp(dt))/g;
    }
    my $prep = $dbh->prepare($sql);
    $prep->execute();
    my $arrayref = $dbh->selectall_arrayref($prep, { Slice => {} });
    return $arrayref;
}

1;
