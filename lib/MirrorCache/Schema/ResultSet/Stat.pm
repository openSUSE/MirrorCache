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


sub prev_minute {
    shift->_prev_period('minute');
}

sub prev_hour {
    shift->_prev_period('hour');
}

sub prev_day {
    shift->_prev_period('day');
}

sub curr {
    my ($self, $period) = @_;
    my $dbh     = $self->result_source->schema->storage->dbh;

    my $sql = <<"END_SQL";
select
sum(case when mirror_id >= 0 and dt > date_trunc('minute', now()) then 1 else 0 end) as hit_minute,
sum(case when mirror_id = -1 and dt > date_trunc('minute', now()) then 1 else 0 end) as miss_minute,
sum(case when mirror_id < -1 and dt > date_trunc('minute', now()) then 1 else 0 end) as geo_minute,
sum(case when mirror_id >= 0 and dt > date_trunc('hour', now()) then 1 else 0 end) as hit_hour,
sum(case when mirror_id = -1 and dt > date_trunc('hour', now()) then 1 else 0 end) as miss_hour,
sum(case when mirror_id < -1 and dt > date_trunc('hour', now()) then 1 else 0 end) as geo_hour,
sum(case when mirror_id >= 0 then 1 else 0 end) as hit_day,
sum(case when mirror_id = -1 then 1 else 0 end) as miss_day,
sum(case when mirror_id < -1 then 1 else 0 end) as geo_day
from stat
where dt > date_trunc('day', now());
END_SQL
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
sum(case when mirror_id < -1 then hit_count else 0 end) as geo
from stat_agg
where period = '$period'::stat_period_t and dt = (select max(dt) from stat_agg where period = '$period'::stat_period_t)
group by dt;
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute();
    return $dbh->selectrow_hashref($prep);
}

sub latest_hit {
    my ($self, $prev_stat_id) = @_;
    $prev_stat_id = 0 unless $prev_stat_id;
    my $dbh     = $self->result_source->schema->storage->dbh;

    my $sql = <<"END_SQL";
select stat.id, mirror_id, stat.country,
       concat(case when secure then 'https://' else 'http://' end, server.hostname, server.urldir, case when metalink then regexp_replace(path, '(.*)\.metalink', E'\\1') else path end) as url,
       substring(path,'(^(/.*)+)/') as folder
       from stat join server on mirror_id = server.id
       where stat.id > ?
       order by stat.id desc
       limit 1
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute($prev_stat_id);
    return $dbh->selectrow_array($prep);
};

1;
