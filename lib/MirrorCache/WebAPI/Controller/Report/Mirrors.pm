# Copyright (C) 2022,2023 SUSE LLC
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

package MirrorCache::WebAPI::Controller::Report::Mirrors;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON qw(decode_json);

sub index {
    my ($self) = @_;
    my $project  = $self->param('project');
    my $allprojects = $self->mcproject->list_full;
    my $projects    = $self->mcproject->list_full;

    if ($project && $project ne "all") {
        my @projects_new;
        for my $p (@$projects) {
            push @projects_new, $p if (0 == rindex $p->{name},  $project,    0) ||
                                      (0 == rindex $p->{alias}, $project,    0) ||
                                      (0 == rindex $p->{alias}, "c$project", 0) ||
                                      ( lc($project) eq 'tumbleweed' && 0 == rindex $p->{alias}, 'tw', 0  );
        }
        $projects = \@projects_new if scalar(@projects_new);
    }

    my ($report, $dt) = $self->mc->reportmirror->list;
    return $self->render(text => 'Report unavailable', status => 500) unless $report;

    $self->stash;
    return $self->render(
        "report/mirrors/index",
        mirrors     => $report,
        projects    => $projects,
        allprojects => $allprojects
    );
}

1;
