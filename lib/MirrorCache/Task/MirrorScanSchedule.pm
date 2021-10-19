# Copyright (C) 2021 SUSE LLC
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

package MirrorCache::Task::MirrorScanSchedule;
use Mojo::Base 'Mojolicious::Plugin';

sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(mirror_scan_schedule => sub { _run($app, @_) });
}

my $RESCAN = int($ENV{MIRRORCACHE_RESCAN_INTERVAL} // 24 * 60 * 60);
my $DELAY  = int($ENV{MIRRORCACHE_SCHEDULE_RETRY_INTERVAL} // 10);
my $EXPIRE = int($ENV{MIRRORCACHE_SCHEDULE_EXPIRE_INTERVAL} // 14 * 24 * 60 * 60);

sub _run {
    my ($app, $job) = @_;
    my $job_id = $job->id;
    my $pref = "[rescan $job_id]";

    my $minion = $app->minion;

    # prevent multiple scheduling tasks to run in parallel
    return $job->finish('Previous job is still active')
      unless my $guard = $minion->guard('mirror_scan_schedule', 60);

    my $schema = $app->schema;
    my $limit = 100;

    # retry later if many jobs are scheduled according to estimation
    my $cnt = $app->backstage->estimate_inactive_jobs('mirror_scan');
    return $job->retry({delay => 30}) if $cnt > 100;

    my @folders = $schema->resultset('Folder')->search({
        scan_requested => { '>', \"COALESCE(scan_scheduled, scan_requested - interval '1 second')" }
    }, {
        order_by => { -asc => [qw/scan_scheduled scan_requested/] },
        rows => $limit
    });
    $cnt = 0;

    for my $folder (@folders) {
        $folder->update({scan_scheduled => \'NOW()'});
        $minion->enqueue('mirror_scan' => [$folder->path] => {notes => {$folder->path => 1}} );
        $cnt = $cnt + 1;
    }

    $job->note(count => $cnt, rescan => $RESCAN);
    $schema->storage->dbh->prepare(
        "update folder set scan_requested = now() where id in
        (
            select id from folder
            where scan_requested < now() - interval '$RESCAN second' and
                  scan_requested < scan_scheduled and
                  wanted > now() - interval '$EXPIRE second'
            order by scan_requested limit 20
        )"
    )->execute();

    return $job->finish unless $DELAY;
    return $job->retry({delay => $DELAY});
}

1;
