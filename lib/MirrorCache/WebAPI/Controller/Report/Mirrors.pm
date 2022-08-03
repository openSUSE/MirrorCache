# Copyright (C) 2022 SUSE LLC
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
use Mojo::JSON qw(decode_json encode_json);

sub index {
    my ($self) = @_;
    my $project  = $self->param('project');
    my $projects = $self->mcproject->list_full;

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

    my $sql = 'select dt, body from report_body where report_id = 1 order by dt desc limit 1';

    eval {
        my @res = $self->schema->storage->dbh->selectrow_array($sql);
        my $body = $res[1];
        my $hash = decode_json($body);

        $self->stash;
        $self->render(
            "report/mirrors/index",
            mirrors  => $hash,
            projects => $projects
        );
    };
    my $error = $@;
    if ($error) {
         print STDERR "RESPMIRRORSREPORT : " . $error . "\n";
         return $self->render(json => {error => $error}, status => 404);
    }
}

1;
