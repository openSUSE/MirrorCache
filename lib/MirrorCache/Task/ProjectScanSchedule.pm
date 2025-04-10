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

package MirrorCache::Task::ProjectSyncSchedule;
use Mojo::Base 'Mojolicious::Plugin';

use DateTime;

sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(project_sync_schedule => sub { _run($app, @_) });
}

my $RESYNC = int($ENV{MIRRORCACHE_RESYNC_INTERVAL} // 24 * 60 * 60);
my $DELAY  = int($ENV{MIRRORCACHE_SCHEDULE_RETRY_INTERVAL} // 10);
my $EXPIRE = int($ENV{MIRRORCACHE_SCHEDULE_EXPIRE_INTERVAL} // 14 * 24 * 60 * 60);
my $RECKLESS=int($ENV{MIRRORCACHE_RECKLESS} // 0);

$RESYNC=0 if $RECKLESS;

sub _run {
    my ($app, $job, $once) = @_;

    my $minion = $app->minion;

    # prevent multiple scheduling tasks to run in parallel
    return $job->finish('Previous project scan schedule job is still active')
      unless my $guard = $minion->guard('_project_scan_schedule', 60);

    my $schema = $app->schema;
    my $limit = 100;

    my @projects;
    my $rs = $schema->resultset('Project');

    my $columns = [ \"now() <= coalesce(me.db_sync_last + interval me.db_sync_every hour, now())" ];
    $columns = [ \"now() <= coalesce(me.db_sync_last + me.db_sync_every * interval '1 hour', now())" ] if $schema->pg;

    @projects = $rs->search({
        db_sync_every => { '>', 0 },
    }, {
      '+select' => $columns,
      '+as'     => [ 'needsync' ],
    });

    my $cnt = 0;

    for my $project (@projects) {
        my $needsync = $project->get_column('needsync');
        next unless $needsync;
        $rs->mark_scheduled($project->id);
        $app->backstage->enqueue('folder_sync', $project->path, 1);
        $cnt++;
    }
    $job->note(count => $cnt);

    return $job->finish unless $DELAY;
    return $job->finish if $once && $once eq 'once';
    return $job->retry({delay => $DELAY});
}

1;
