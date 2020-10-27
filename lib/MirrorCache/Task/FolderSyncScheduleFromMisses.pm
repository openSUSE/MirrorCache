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

package MirrorCache::Task::FolderSyncScheduleFromMisses;
use Mojo::Base 'Mojolicious::Plugin';

use DateTime;

sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(folder_sync_schedule_from_misses => sub { _run($app, @_) });
}

sub _run {
    my ($app, $job, $prev_event_log_id) = @_;
    my $job_id = $job->id;
    my $pref = "[schedule_from_misses $job_id]";
    my $id_in_notes = $job->info->{notes}{event_log_id};
    $prev_event_log_id = $id_in_notes if $id_in_notes;
    print(STDERR "$pref read id from notes: $id_in_notes\n") if $id_in_notes;
    print(STDERR "$pref use id from param: $prev_event_log_id\n") if $prev_event_log_id && (!$id_in_notes || $prev_event_log_id != $id_in_notes);

    my $minion = $app->minion;
    # prevent multiple scheduling tasks to run in parallel
    return $job->finish('Previous schedule_from_misses job is still active')
      unless my $guard = $minion->guard('folder_sync_schedule_from_misses', 86400);

    my $schema = $app->schema;
    my $limit = 1000;

    my ($event_log_id, $path_country_map, $country_list) = $schema->resultset('AuditEvent')->path_misses($prev_event_log_id, $limit);

    my $rs = $schema->resultset('Folder');
    my $last_run = 0;
    while (scalar(%$path_country_map)) {
        my $cnt = 0;
        $prev_event_log_id = $event_log_id;
        print(STDERR "$pref read id from event log up to: $event_log_id\n");
        for my $path (sort keys %$path_country_map) {
            my $folder = $rs->find({ path => $path });
            if (!$folder) {
                if (!$app->mc->root->is_dir($path)) {
                    $path = Mojo::File->new($path)->dirname;
                    next unless $app->mc->root->is_dir($path);
                }
            }
            $rs->request_db_sync( $path, $path_country_map->{$path} );
            $cnt = $cnt + 1;
        }
        for my $country (@$country_list) {
            next unless $minion->lock('mirror_probe_scheduled_' . $country, 60); # don't schedule if schedule hapened in last 60 sec
            next unless $minion->lock('mirror_probe_incomplete_for_' . $country, 6000); # don't schedule until probe job completed
            $minion->unlock('mirror_force_done');
            $minion->enqueue('mirror_probe' => [$country] => {priority => 9});
        }
        last unless $cnt;
        $last_run = $last_run + $cnt;
        ($event_log_id, $path_country_map, $country_list) = $schema->resultset('AuditEvent')->path_misses($prev_event_log_id, $limit);
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
    return $job->retry({delay => 5});
}

1;
