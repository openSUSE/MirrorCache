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

my $DELAY   = int($ENV{MIRRORCACHE_SCHEDULE_RETRY_INTERVAL} // 5);
my $TIMEOUT = int($ENV{MIRRORCACHE_COUNTRY_RESCAN_TIMEOUT} // 120);

sub _run {
    my ($app, $job) = @_;
    my $job_id = $job->id;
    my $pref = "[rescan $job_id]";

    my $minion = $app->minion;
    # prevent multiple scheduling tasks to run in parallel
    return $job->finish('Previous job is still active')
      unless my $guard = $minion->guard('mirror_scan_reschedule', 60);

    my $schema = $app->schema;

    my $sql = <<'END_SQL';
update demand
set last_scan = now()
from (
    select folder_id, country
    from demand
    where (folder_id, country) in (
        select folder_id, country
        from demand
        where last_request > last_scan and last_scan < now() - interval '15 second'
        order by last_request limit 100
    )
) sub
join folder on folder.id = folder_id
where (demand.folder_id, demand.country) = (sub.folder_id, sub.country)
returning folder.path, demand.country
END_SQL

    my $dbh = $schema->storage->dbh;

    my $prep = $dbh->prepare($sql);
    my $xxx = $prep->execute;
    my $arrayref =  $dbh->selectrow_hashref($prep);
    # my $arrayref =  $dbh->selectall_arrayref($prep);

    print STDERR $app->dumper('XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX', $xxx, $arrayref);

    # foreach my $row ( @$arrayref ) {
    #    $minion->enqueue('mirror_scan' => [$row->{path}, $row->{country}] => {priority => 7});
    # }
    return $job->retry({delay => $DELAY});
}

1;
