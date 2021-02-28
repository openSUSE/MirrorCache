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
    
    $job->retry({delay => 15});
}

sub _agg {
    my ($app, $job, $period) = @_;
    eval {    
        $app->schema->storage->dbh->prepare(
"insert into stat_agg select dt_to, '$period'::stat_period_t, stat.mirror_id, count(*)
from
( select date_trunc('$period', now()) - interval '1 $period' as dt_from, date_trunc('$period', now()) as dt_to ) x
join stat on dt between x.dt_from and x.dt_to
left join stat_agg on period = '$period'::stat_period_t and stat_agg.dt = x.dt_to
where
stat_agg.period is NULL
group by stat.mirror_id, x.dt_to;"
        )->execute();
        1;
    } or $job->note("last_warning_$period" => $@, "last_warning_$period" . "_at" => datetime_now());
}

1;
