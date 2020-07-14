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

package MirrorCache::Task::FolderSyncSchedule;
use Mojo::Base 'Mojolicious::Plugin';

use DateTime;

sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(folder_sync_schedule => sub { _run($app, @_) });
}

sub _run {
    my ($app, $job) = @_;

    my $minion = $app->minion;

    # prevent multiple scheduling tasks to run in parallel
    return $job->finish('Previous folder sync schedule job is still active')
      unless my $guard = $minion->guard('folder_sync_schedule', 86400);

    my $schema = $app->schema;
    my $limit = 1000;

    # retry later if some sync_folder jobs are active (TODO improve it)
    my $cnt = $minion->jobs({states => ['inactive', 'active'], tasks => ['sync_folder']})->total;
    return $job->retry({delay => 30}) if $cnt;

    my @folders = $schema->resultset('Folder')->search({
        db_sync_scheduled => { '!=', undef } 
    }, {
        order_by => { -asc => [qw/db_sync_scheduled -db_sync_priority/] },
        rows => $limit
    });
    
    for my $folder (@folders) {
        $minion->enqueue('folder_sync' => [$folder->path] => {priority => $folder->db_sync_priority} => {notes => {$folder->path => 1}} );
        $cnt = $cnt + 1;
    }
    $job->note(count => $cnt);
    $app->backstage->enqueue_unless_scheduled(folder_sync_schedule => [] => {delay => 30});
    return $job->finish($cnt);
}

1;
