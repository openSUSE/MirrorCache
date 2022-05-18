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
sum(case when                                                                             lower(agent) ~ '$BOT_MASK'  then 1 else 0 end)  as bot_day
from stat
where dt > date_trunc('day', CURRENT_TIMESTAMP(3))
END_SQL


my $SQLCURR_MARIADB = <<"END_SQL";
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
from stat
where dt > date_sub(CURRENT_TIMESTAMP(3), interval 1 day)
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

sub mycurr {
    my ($self, $ip_sha1) = @_;
    my $dbh = $self->result_source->schema->storage->dbh;

    my $sql;
    if ($dbh->{Driver}->{Name} eq 'Pg') {
        $sql = $SQLCURR_PG;
    } else {
        $sql = $SQLCURR_MARIADB;
    }
    $sql = $sql . ' and ip_sha1 = ?';

    my $prep = $dbh->prepare($sql);
    $prep->execute($ip_sha1);
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
where period = '$period'::stat_period_t and dt = (select max(dt) from stat_agg where period = '$period'::stat_period_t)
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
       concat(case when secure then 'https://' else 'http://' end, CASE WHEN length(server.hostname_vpn)>0 THEN server.hostname_vpn ELSE server.hostname END, server.urldir, case when metalink then regexp_replace(path, '(.*)\.metalink', E'\\1') else path end) as url,
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

sub path_misses {
    my ($self, $prev_stat_id, $limit) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = << 'END_SQL';
select * from (
select stat.id, stat.path, stat.folder_id, trim(country)
from stat left join folder on folder.id = stat.folder_id
where mirror_id < 1
and ( mirror_id in (0,-1) or mirrorlist )
and file_id is null
and stat.path !~ '.*\/(repodata\/repomd.xml[^\/]*|media\.1\/media|.*\.sha256(\.asc)|Release(.key|.gpg)?|InRelease|Packages(.gz)?|Sources(.gz)?|.*_Arch\.(files|db|key)(\.(sig|tar\.gz(\.sig)?))?|(files|primary|other).xml.gz)$'
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

1;
