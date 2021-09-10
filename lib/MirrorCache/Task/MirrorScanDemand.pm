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

package MirrorCache::Task::MirrorScanDemand;
use Mojo::Base 'Mojolicious::Plugin';

sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(mirror_scan_demand => sub { _run($app, @_) });
}

my $TIMEOUT = int($ENV{MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT} // 120);

sub _run {
    my ($app, $job, $path) = @_;
    return $job->fail('Empty path is not allowed') unless $path;
    return $job->fail('Trailing slash is forbidden') if '/' eq substr($path,-1) && $path ne '/';

    my $job_id = $job->id;
    my $minion = $app->minion;
    # prevent multiple scheduling tasks to run in parallel
    return $job->finish('Previous job is still active')
      unless my $guard = $minion->guard('mirror_scan_demand_' . $path, 8640);

    my $schema = $app->schema;
    my $folder = $schema->resultset('Folder')->find({path => $path});
    my $folder_id = $folder->id if $folder;
    return $job->finish("Cannot find folder {$path}") unless $folder && $folder_id; # folder is not added to db yet

    my %seen = ();

    for my $demand ($schema->resultset('DemandMirrorlist')->search({folder_id => $folder_id, last_request => { '>=', \'COALESCE(last_scan, last_request)' }})) {
        if ($TIMEOUT) {
            my $bool = $minion->lock("mirror_scan_schedule_mirrorlist_$path", $TIMEOUT);
            next unless $bool;
        }
        $minion->enqueue('mirror_scan' => [$path] => {priority => 7});
        $seen{$path} = 1;
        $job->note("mirrorlist" => 1);
    }

    for my $demand ($schema->resultset('Demand')->search({folder_id => $folder_id, last_request => { '>=', \'COALESCE(last_scan, last_request)' }})) {
        next unless my $country = $demand->country;
        next if $seen{path};
        if ($TIMEOUT) {
            my $bool = $minion->lock("mirror_scan_schedule_$path" . "_$country", $TIMEOUT);
            next unless $bool;
        }
        $minion->enqueue('mirror_scan' => [$path, $country] => {priority => 7});
        $job->note($country => 1);
    }

    return $job->finish;
}

1;
