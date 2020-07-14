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

package MirrorCache::Task::MirrorScanScheduleFromProbeErrors;
use Mojo::Base 'Mojolicious::Plugin';

use DateTime;

sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(mirror_scan_schedule_from_probe_errors => sub { _run($app, @_) });
}

sub _run {
    my ($app, $job, $prev_event_log_id) = @_;

    # prevent multiple scheduling tasks to run in parallel
    return $job->finish('Previous schedule_from_probe_errors job is still active')
      unless my $guard = $app->minion->guard('mirror_scan_schedule_from_probe_errors', 86400);

    my $schema = $app->schema;
    my $minion = $app->minion;
    my $limit = 1000;

    my ($event_log_id, $paths) = $schema->resultset('AuditEvent')->mirror_probe_errors($prev_event_log_id, $limit);

    my $cnt = 0;
    while (scalar(@$paths)) {
        for my $path (@$paths) {
            $minion->enqueue('mirror_scan' => [$path] => {priority => 10});
            $cnt = $cnt + 1;
        }
        $paths = $schema->resultset('AuditEvent')->mirror_probe_errors($event_log_id, $limit);
    }
    $job->note(count => $cnt);
    $app->backstage->enqueue_unless_scheduled(mirror_scan_schedule_from_probe_errors => [$event_log_id] => {delay => 5});
}

1;
