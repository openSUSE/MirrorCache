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

package MirrorCache::Task::StatAggSchedule;
use Mojo::Base 'Mojolicious::Plugin';
use MirrorCache::Utils 'datetime_now';

sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(stat_agg_schedule => sub { _run($app, @_) });
}

my $DELAY   = int($ENV{MIRRORCACHE_SCHEDULE_STAT_RETRY_INTERVAL} // 15);

sub _run {
    my ($app, $job) = @_;

    my $minion = $app->minion;

    # prevent multiple scheduling tasks to run in parallel
    return $job->finish('Previous stat agg sync schedule job is still active')
      unless my $guard = $minion->guard('stat_agg_schedule', 86400);


    if ($minion->lock('stat_agg_schedule_minute', 10)) {
        _agg($app, $job, 'minute');
    }

    if ($minion->lock('stat_agg_schedule_hour', 5*60)) {
        _agg($app, $job, 'hour');
    }

    if ($minion->lock('stat_agg_schedule_day', 15*60)) {
        _agg($app, $job, 'day');
    }

    return $job->finish unless $DELAY;
    $job->retry({delay => $DELAY});
}

my $BOT_MASK = $ENV{MIRRORCACHE_BOT_MASK} // '.*(bot|rclone).*';

sub _agg {
    my ($app, $job, $period) = @_;

    my $dbh = $app->schema->storage->dbh;
    my $sql = "
insert into stat_agg select dt_to, '$period'::stat_period_t, case when agent ~ '$BOT_MASK' then -100 else stat.mirror_id end, count(*)
from
( select date_trunc('$period', CURRENT_TIMESTAMP(3)) - interval '1 $period' as dt_from, date_trunc('$period', CURRENT_TIMESTAMP(3)) as dt_to ) x
join stat on dt between x.dt_from and x.dt_to
left join stat_agg on period = '$period'::stat_period_t and stat_agg.dt = x.dt_to
where
stat_agg.period is NULL
group by case when agent ~ '$BOT_MASK' then -100 else stat.mirror_id end, x.dt_to
";

    if ($dbh->{Driver}->{Name} ne 'Pg') {
        my $format = '%Y-%m-%d-%H:00';
        $format = '%Y-%m-%d-00:00' if $period eq 'day';
        $format = '%Y-%m-%d-%H:%i' if $period eq 'minute';

        $sql = "
insert into stat_agg select dt_to, '$period', case when agent regexp '$BOT_MASK' then -100 else stat.mirror_id end, count(*)
from
( select date_sub(CONVERT(DATE_FORMAT(now(),'$format'),DATETIME), interval 1 $period) as dt_from, CONVERT(DATE_FORMAT(now(),'$format'),DATETIME) as dt_to ) x
join stat on dt between x.dt_from and x.dt_to
left join stat_agg on period = '$period' and stat_agg.dt = x.dt_to
where
stat_agg.period is NULL
group by case when agent regexp '$BOT_MASK' then -100 else stat.mirror_id end, x.dt_to
";
    };

    eval {
        $dbh->prepare($sql)->execute;
        1;
    } or $job->note("last_warning_$period" => $@, "last_warning_$period" . "_at" => datetime_now());
}

1;
