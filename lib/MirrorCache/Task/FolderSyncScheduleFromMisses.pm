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

    my ($event_log_id, $paths) = $schema->resultset('AuditEvent')->path_misses($prev_event_log_id, $limit);

    my $rs = $schema->resultset('Folder');
    while (scalar(@$paths)) {
        my $cnt = 0;
        $prev_event_log_id = $event_log_id;
        print(STDERR "$pref read id from event log up to: $event_log_id\n");
        for my $path (@$paths) {
            my $folder = $rs->find({ path => $path });
            if (!$folder) {
                if (!$app->mc->root->is_dir($path)) {
                    $path = Mojo::File->new($path)->dirname;
                    next unless $app->mc->root->is_dir($path);
                }
            }
            $rs->request_db_sync( $path );
            $cnt = $cnt + 1;
        }
        last unless $cnt;
        ($event_log_id, $paths) = $schema->resultset('AuditEvent')->path_misses($prev_event_log_id, $limit);
    }
    print(STDERR "$pref will retry with id: $prev_event_log_id\n");
    $job->note(event_log_id => $prev_event_log_id);
    return $job->retry({delay => 5});
}

1;
