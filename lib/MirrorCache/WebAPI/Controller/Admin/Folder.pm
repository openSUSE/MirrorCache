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

package MirrorCache::WebAPI::Controller::Admin::Folder;
use Mojo::Base 'Mojolicious::Controller';

sub delete_cascade {
    my ($c, $only_diff) = @_;
    my $id = $c->param('id');

    my $tx = $c->render_later()->tx;
    Mojo::IOLoop->subprocess(
        sub {
            $c->schema->resultset('Folder')->delete_cascade($id, $only_diff);
        },
        sub {
            my ($self, $err, @result) = @_;
            return $c->render(text => $err, status => 500) if $err;
            return $c->render(text => 'ok');
            my $txkeep = $tx;
        }
    );
}

sub delete_diff {
    shift->delete_cascade(1);
}

1;
