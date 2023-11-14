# Copyright (C) 2023 SUSE LLC
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

package MirrorCache::WebAPI::Controller::Rest::ServerCheckFile;
use Mojo::Base 'Mojolicious::Controller';
use Data::Dumper;

sub start {
    my ($self) = @_;

    my $path = $self->param("file");
    return $self->render(code => 400, text => "Mandatory argument is missing") unless $path;

    my $job_id;
    eval {
        $job_id = $self->minion->enqueue('mirror_file_check' => [$path]);
    };
    return $self->render(code => 500, text => Dumper($@)) unless $job_id;

    return $self->render(
        json => {
            job_id     => $job_id,
        }
    );
}

1;
