# Copyright (C) 2022,2024 SUSE LLC
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

package MirrorCache::WebAPI::Controller::Rest::Project;
use Mojo::Base 'Mojolicious::Controller';

sub show {
    my ($self) = @_;
    my $name = $self->param("name");
    return $self->render(code => 400, text => "Mandatory argument is missing") unless $name;

    my $prj = $self->schema->resultset('Project')->find({ name => $name });

    $self->render(json => {$prj->get_columns});
}

sub list {
    my ($self) = @_;

    my $list = $self->mcproject->list_full;

    $self->render(json => $list);
}

sub last_modified {
    my ($self) = @_;

    my $name = $self->param("project");
    my $prj = $self->schema->resultset('Project')->find({ name => $name });

    return $self->render(text => 'Not found', status => 404) unless $prj && $prj->id;
    return $self->render(text => 'No data', status => 201) unless $prj->lm;
    $self->render(text => $prj->lm, status => 200);
}

sub disk_usage {
    my ($self) = @_;

    my $name = $self->param("project");
    my $prj = $self->schema->resultset('Project')->find({ name => $name });

    return $self->render(text => 'Not found', status => 404) unless $prj && $prj->id;
    return $self->render(text => 'No data', status => 201) unless defined $prj->size;
    $self->render(text => $prj->size, status => 200);
}

1;
