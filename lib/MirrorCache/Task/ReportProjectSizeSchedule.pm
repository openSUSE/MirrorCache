# Copyright (C) 2024 SUSE LLC
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

package MirrorCache::Task::ReportProjectSizeSchedule;
use Mojo::Base 'Mojolicious::Plugin';
use DateTime;

sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(report_project_size_schedule => sub { _run($app, @_) });
}

my $HASHES_QUEUE   = $ENV{MIRRORCACHE_HASHES_QUEUE} // 'hashes';
my $DELAY = int($ENV{MIRRORCACHE_SCHEDULE_REPORT_PROJECT_SIZE_SCHEDULE_RETRY_INTERVAL} // 12 * 60 * 60);

sub _run {
    my ($app, $job, $once) = @_;
    my $minion = $app->minion;
    return $job->finish('Previous report job is still active')
      unless my $guard = $minion->guard('report_project_size_schedule', 2*60*60);

    my $schema = $app->schema;
    my @projects = $schema->resultset('Project')->all;
    my $sunday = DateTime->today->day_of_week;
    $sunday = 0 unless $sunday == 7;
    for my $proj (@projects) {
        my $path = $proj->path;
        my $prio = $proj->prio // 1;
        next if !$sunday && $prio < 1;
        $minion->enqueue('report_project_size' => [ $proj->path ] => {priority => 15} => {queue => $HASHES_QUEUE});
    }

    return $job->finish if $once;
    return $job->retry({delay => $DELAY});
}

1;
