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

package MirrorCache::Task::StatAgg;
use Mojo::Base 'Mojolicious::Plugin';

use DateTime;

sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(stat_agg_minute => sub { _run($app, 'minute', @_) });
    $app->minion->add_task(stat_agg_hour   => sub { _run($app, 'hour',   @_) });
    $app->minion->add_task(stat_agg_day    => sub { _run($app, 'day',    @_) });
    $app->minion->add_task(stat_agg_month  => sub { _run($app, 'month',  @_) });
    $app->minion->add_task(stat_agg_year   => sub { _run($app, 'year',   @_) });
}

sub _run {
    my ($app, $period, $job) = @_;

    my $minion = $app->minion;

    # prevent multiple scheduling tasks to run in parallel
    return $job->finish('Previous stat agg job is still active')
      unless my $guard = $minion->guard('stat_agg_' . $period, 360);

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
    } or $job->fail($@);
}

1;
