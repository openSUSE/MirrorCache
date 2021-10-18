# Copyright (C) 2020,2021 SUSE LLC
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

package MirrorCache::Task::MirrorScanScheduleFromPathErrors;
use Mojo::Base 'Mojolicious::Plugin';

sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(mirror_scan_schedule_from_path_errors => sub { _run($app, @_) });
}

my $DELAY   = int($ENV{MIRRORCACHE_SCHEDULE_RETRY_INTERVAL} // 5);

sub _run {
    my ($app, $job, $prev_event_log_id) = @_;
    my $job_id = $job->id;
    my $pref = "[scan_from_path_errors $job_id]";
    my $id_in_notes = $job->info->{notes}{event_log_id};
    $prev_event_log_id = $id_in_notes if $id_in_notes;
    print(STDERR "$pref read id from notes: $id_in_notes\n") if $id_in_notes;
    print(STDERR "$pref use id from param: $prev_event_log_id\n") if $prev_event_log_id && (!$id_in_notes || $prev_event_log_id != $id_in_notes);

    my $minion = $app->minion;
    # prevent multiple scheduling tasks to run in parallel
    return $job->finish('Previous schedule_from_path_errors job is still active')
      unless my $guard = $minion->guard('mirror_scan_schedule_from_path_errors', 86400);

    my $schema = $app->schema;
    my $limit = $prev_event_log_id? 20 : 10;
    my ($event_log_id, $resync_ids, $rescan_ids, $country_list) = $schema->resultset('AuditEvent')->mirror_path_errors($prev_event_log_id, $limit);
    my $last_run = 0;
    my $rs = $schema->resultset('Folder');
    while ($resync_ids || $rescan_ids) {
        my $cnt = 0;
        $prev_event_log_id = $event_log_id;
        print(STDERR "$pref read id from event log up to: $event_log_id\n");
        if ($resync_ids) {
            $rs->request_sync_array(@$resync_ids);
            $cnt += @$resync_ids;
        }
        if ($rescan_ids) {
            $rs->request_scan_array(@$rescan_ids);
            $cnt += @$rescan_ids;
        }
        for my $country (@$country_list) {
            next unless $minion->lock('mirror_probe_scheduled_' . $country, 60); # don't schedule if schedule hapened in last 60 sec
            next unless $minion->lock('mirror_probe_incomplete_for_' . $country, 300); # don't schedule until probe job completed
            $minion->unlock('mirror_force_done');
            $minion->enqueue('mirror_probe' => [$country] => {priority => 6});
        }
        $last_run = $last_run + $cnt;
        last unless $cnt;
        $limit = 20;
        ($event_log_id, $resync_ids, $rescan_ids, $country_list) = $schema->resultset('AuditEvent')->mirror_path_errors($prev_event_log_id, $limit);
    }

    if ($minion->lock('mirror_force_done', 9000)) {
        if ($minion->lock('schedule_mirror_force_ups', 9000)) {
            $minion->enqueue('mirror_force_ups' => [] => {priority => 10});
        }

        if ($minion->lock('schedule_mirror_force_downs', 300)) {
            $minion->enqueue('mirror_force_downs' => [] => {priority => 10});
        }
    }

    $prev_event_log_id = 0 unless $prev_event_log_id;
    print(STDERR "$pref will retry with id: $prev_event_log_id\n");
    my $total = $job->info->{notes}{total};
    $total = 0 unless $total;
    $job->note(event_log_id => $prev_event_log_id, total => $total, last_run => $last_run);

    return $job->finish unless $DELAY;
    return $job->retry({delay => $DELAY});
}

1;
