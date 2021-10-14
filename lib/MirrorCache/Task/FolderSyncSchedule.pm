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

my $DELAY = int($ENV{MIRRORCACHE_SCHEDULE_RETRY_INTERVAL} // 10);

sub _run {
    my ($app, $job) = @_;

    my $minion = $app->minion;

    # prevent multiple scheduling tasks to run in parallel
    return $job->finish('Previous folder sync schedule job is still active')
      unless my $guard = $minion->guard('folder_sync_schedule', 60);

    my $schema = $app->schema;
    my $limit = 1000;

    # retry later if many folder_sync jobs are scheduled according to estimation
    my $cnt = $app->backstage->estimate_inactive_jobs('sync_folder');
    return $job->retry({delay => 30}) if $cnt > 100;

    my @folders = $schema->resultset('Folder')->search({
        sync_requested => { '>', \"COALESCE(sync_scheduled - 1*interval '1 second', sync_requested - 1*interval '1 second')" }
    }, {
        order_by => { -asc => [qw/sync_requested/] },
        rows => $limit
    });

    for my $folder (@folders) {
        $folder->update({sync_scheduled => \'NOW()'});
        $minion->enqueue('folder_sync' => [$folder->path] => {notes => {$folder->path => 1}} );
        $cnt = $cnt + 1;
    }
    $job->note(count => $cnt);
    $schema->storage->dbh->prepare(
        "update folder set sync_requested = now() where id in ( select id from folder where sync_requested < now() - interval '2 hour' and sync_requested < sync_scheduled order by sync_requested limit 50)"
    )->execute();
    return $job->finish unless $DELAY;
    return $job->retry({delay => $DELAY});
}

1;
