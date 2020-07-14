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

    my $minion = $app->minion;
    # prevent multiple scheduling tasks to run in parallel
    return $job->finish('Previous schedule_from_misses job is still active')
      unless my $guard = $minion->guard('folder_sync_schedule_from_misses', 86400);

    my $schema = $app->schema;
    my $limit = 1000;

    my ($event_log_id, $paths) = $schema->resultset('AuditEvent')->path_misses($prev_event_log_id, $limit);

    my $cnt = 0;
    my $rs = $schema->resultset('Folder');
    while (scalar(@$paths)) {
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
        $paths = $schema->resultset('AuditEvent')->path_misses($event_log_id, $limit);
    }
    $job->note(count => $cnt);
    $app->backstage->enqueue_unless_scheduled(folder_sync_schedule_from_misses => [$event_log_id] => {delay => 5});
}

1;
