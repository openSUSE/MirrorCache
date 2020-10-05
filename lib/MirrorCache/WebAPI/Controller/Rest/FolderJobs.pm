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

package MirrorCache::WebAPI::Controller::Rest::FolderJobs;
use Mojo::Base 'Mojolicious::Controller';
use Data::Dumper;

sub list {
    my ($self) = @_;

    my $id = $self->param("id");

    my $path;
    eval {
        my $rs = $self->schema->resultset('Folder');
        $path = $rs->find($id)->path;
    };
    my $error = $@;
    if ($error) {
        return $self->render(json => {error => $error}, status => 404);
    }

    my $minion_backend = $self->minion->backend;

    my %res;
    my $sync_latest_id = 0;
    my $sync_running_count = 0;
    my $jobs = $minion_backend->list_jobs(0, 100,
        {tasks => ['folder_sync'], notes => [$path]})->{jobs};

    for my $job (@$jobs) {
        $sync_running_count = $sync_running_count+1 if ($job->{status} eq 'active' || $job->{status} eq 'inactive');
        $sync_latest_id     = $job->{id} if $job->{id} > $sync_latest_id;
    }

    my $scan_latest_id = 0;
    my $scan_running_count = 0;
    $jobs = $minion_backend->list_jobs(0, 100,
        {tasks => ['mirror_scan'], notes => [$path]})->{jobs};

    for my $job (@$jobs) {
        $scan_running_count = $scan_running_count+1 if ($job->{status} eq 'active' || $job->{status} eq 'inactive');
        $scan_latest_id     = $job->{id} if $job->{id} > $scan_latest_id;
    }

    $self->render(
        json => {
            sync_latest_id     => $sync_latest_id,
            sync_running_count => $sync_running_count,
            scan_latest_id     => $scan_latest_id,
            scan_running_count => $scan_running_count,
        }
    );
}

1;
