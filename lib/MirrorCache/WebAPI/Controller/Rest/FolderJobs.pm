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
use Mojo::Promise;
use Data::Dumper;

sub list {
    my ($self) = @_;

    my $id = $self->param("id");

    my $path;
    my $tx = $self->render_later->tx;
    my $p = Mojo::Promise->new->timeout(5);
    $p->then(sub {
        $path = $self->schema->resultset('Folder')->find($id)->path;
    }, sub {
        my @reason = @_;
        my $reason = scalar(@reason)? Dumper(@reason) : 'unknown';
        $self->render(json => {error => $reason}, status => 404);
    })->then(sub {
        my $minion_backend = $self->minion->backend;
        my %counts;
        my $jobs = $minion_backend->list_jobs(0, 100,
            {tasks => ['folder_sync','mirror_scan'], notes => [$path], states => ['active', 'inactive']})->{jobs};

        for my $job (@$jobs) {
            $counts{$job->{task} . $job->{state}}++;
        }
        $self->render(
            json => {
                sync_waiting_count => $counts{'folder_syncinactive'} // 0,
                sync_running_count => $counts{'folder_syncactive'}   // 0,
                scan_waiting_count => $counts{'mirror_scaninactive'} // 0,
                scan_running_count => $counts{'mirror_scanactive'}   // 0,
            }
        );
    }, sub {
        my @reason = @_;
        my $reason = scalar(@reason)? Dumper(@reason) : 'unknown';
        $self->render(json => {error => $reason}, status => 500);
        my $txkeep = $tx;
    });

    $p->resolve;

}

1;
