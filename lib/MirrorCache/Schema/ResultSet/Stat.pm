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
x.per,
sum(case when mirror_id >= 0 then 1 else 0 end) as hit,
sum(case when mirror_id = -1 then 1 else 0 end) as miss,
sum(case when mirror_id < -1 then 1 else 0 end) as geo
from
(select 'minute' per
union select 'hour' per
union select 'day' per) x
join stat on stat.dt > date_trunc(x.per, now())
group by x.per
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute();
    return $dbh->selectall_hashref($prep, 'per', {});
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

1;
