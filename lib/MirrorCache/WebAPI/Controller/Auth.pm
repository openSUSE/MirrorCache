# Copyright (C) 2020,2021 SUSE LLC
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

package MirrorCache::WebAPI::Controller::Auth;
use Mojo::Base 'Mojolicious::Controller';

use MirrorCache::Schema;

sub auth {
    my $self = shift;
    my $reason = "Not authorized";
    my $user = $self->current_user;

    if ($user) {
        $self->stash(current_user => {user => $user});
        return 1;
    }

    $self->render(json => {error => $reason}, status => 403);
    return 0;
}

sub auth_operator {
    my ($self) = @_;
    return 1 if ($self->is_local_request);
    return 0 if (!$self->auth);
    return 1 if ($self->is_operator || $self->is_admin);

    $self->render(json => {error => 'Operator level required'}, status => 403);
    return 0;
}

sub auth_admin {
    my ($self) = @_;
    return 0 if (!$self->auth);
    return 1 if ($self->is_admin);

    $self->render(json => {error => 'Administrator level required'}, status => 403);
    return 0;
}

1;
