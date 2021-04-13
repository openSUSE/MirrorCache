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

package MirrorCache::WebAPI::Controller::Rest::User;
use Mojo::Base 'Mojolicious::Controller';

sub delete {
    my ($self) = @_;
    my $user = $self->schema->resultset('Acc')->find($self->param('id'));
    return $self->render(json => {error => 'Not found'}, status => 404) unless $user;
    my $result = $user->delete();
    my $role = 'user';
    if ($user->is_admin) {
        $role = 'admin'
    } elsif ($user->is_operator) {
        $role = 'operator';
    }
    $self->emit_event('mc_user_delete', {role => $role, username => $user->username});
    $self->render(json => {result => $result});
}

1;
