# Copyright (C) 2024,2025 SUSE LLC
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

package MirrorCache::Task::StatAggPkg;
use Mojo::Base 'Mojolicious::Plugin';
use MirrorCache::Utils 'datetime_now';

sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(stat_agg_pkg => sub { _run($app, @_) });
}

sub _run {
    my ($app, $job) = @_;

    my $minion = $app->minion;

    # prevent multiple scheduling tasks to run in parallel
    return $job->finish('Previous stat agg pkg job is still active')
      unless my $guard = $minion->guard('stat_agg_pkg', 86400);

    if ($minion->lock('stat_agg_pkg_hour', 15*60)) {
        _agg($app, $job, 'hour');
    }

    if ($minion->lock('stat_agg_pkg_day', 2*60*60)) {
        _agg($app, $job, 'day');
    }

    if ($minion->lock('stat_agg_pkg_total', 2*60*60)) {
        _agg_total($app, $job, 'day');
    }
}

sub _agg {
    my ($app, $job, $period) = @_;


    my $dbh = $app->schema->storage->dbh;
    my $sql = "
insert into agg_download_pkg select '$period'::stat_period_t, dt_to, metapkg.id, coalesce(stat.folder_id, 0), stat.country, count(*)
from
( select date_trunc('$period', CURRENT_TIMESTAMP(3)) - interval '1 $period' as dt_from, date_trunc('$period', CURRENT_TIMESTAMP(3)) as dt_to ) x
join stat on dt between x.dt_from and x.dt_to and pkg is not null
join metapkg on name = pkg
left join agg_download_pkg on period = '$period'::stat_period_t and agg_download_pkg.metapkg_id = metapkg.id and agg_download_pkg.dt = x.dt_to and agg_download_pkg.country = stat.country and agg_download_pkg.folder_id = coalesce(stat.folder_id, 0)
where
agg_download_pkg.period is NULL
group by dt_to, metapkg.id, stat.folder_id, stat.country
";

    if ($dbh->{Driver}->{Name} ne 'Pg') {
        my $format = '%Y-%m-%d-%H:00';
        $format = '%Y-%m-%d-00:00' if $period eq 'day';
        $format = '%Y-%m-%d-%H:%i' if $period eq 'minute';

        $sql = "
insert into agg_download_pkg select '$period', dt_to, metapkg.id, coalesce(stat.folder_id, 0), stat.country, count(*)
from
( select date_sub(CONVERT(DATE_FORMAT(now(),'$format'),DATETIME), interval 1 $period) as dt_from, CONVERT(DATE_FORMAT(now(),'$format'),DATETIME) as dt_to ) x
join stat on dt between x.dt_from and x.dt_to and pkg is not null
join metapkg on name = pkg
left join agg_download_pkg on period = '$period' and agg_download_pkg.dt = x.dt_to and agg_download_pkg.metapkg_id = metapkg.id and agg_download_pkg.country = stat.country and agg_download_pkg.folder_id = coalesce(stat.folder_id, 0)
where
agg_download_pkg.period is NULL
group by dt_to, metapkg.id, stat.folder_id, stat.country
";
    };

    eval {
        $dbh->prepare($sql)->execute;
        1;
    } or $job->note("last_warning_$period" => $@, "last_warning_$period" . "_at" => datetime_now());
}


sub _agg_total {
    my ($app, $job) = @_;
    my $period = 'total';

    my $dbh = $app->schema->storage->dbh;
    my $sql = "
insert into agg_download_pkg select '$period'::stat_period_t, date_trunc('day',now()), d1.metapkg_id, d1.folder_id, d1.country, coalesce((select d2.cnt from agg_download_pkg d2 where d2.period = '$period'::stat_period_t and d2.metapkg_id = d1.metapkg_id and d2.folder_id = d1.folder_id and d2.country = d1.country order by d2.dt desc limit 1), 0) + sum(d1.cnt)
from agg_download_pkg d1
cross join ( select coalesce(max(dt), now() - interval '1 year') as dt from agg_download_pkg where period = '$period'::stat_period_t ) gx
where d1.period = 'day'::stat_period_t and d1.dt > gx.dt
group by d1.metapkg_id, d1.folder_id, d1.country
";

    if ($dbh->{Driver}->{Name} ne 'Pg') {
        $sql =~ s/::stat_period_t//g;
        $sql =~ s/interval '1 year'/interval 1 year/g;
        $sql =~ s/date_trunc\('day',now\(\)\)/date(now())/g
    }
    eval {
        $dbh->prepare($sql)->execute;
        1;
    } or $job->note("last_warning_$period" => $@, "last_warning_$period" . "_at" => datetime_now());
}

1;
