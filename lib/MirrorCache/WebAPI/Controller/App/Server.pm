# Copyright (C) 2014 SUSE LLC
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

package MirrorCache::WebAPI::Controller::App::Server;
use Mojo::Base 'MirrorCache::WebAPI::Controller::App::Table';

sub index {
    shift->SUPER::admintable('server');
}

sub update {
    my ($self) = @_;
    my $set  = $self->schema->resultset('Server');

    my $id = $self->param('id');

    my $mirror = $set->find($id);
    if (!$mirror) {
        $self->flash('error', "Can't find mirror {$id}");
    }
    else {
        $self->flash('info', 'Mirror ' . $mirror->hostname . ' updated');
        $self->emit_event('mc_mirror_updated', {hostname => $mirror->hostname});
    }

    $self->redirect_to($self->url_for('server'));
}

1;
