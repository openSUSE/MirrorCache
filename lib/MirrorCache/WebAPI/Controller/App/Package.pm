# Copyright (C) 2024 SUSE LLC
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

package MirrorCache::WebAPI::Controller::App::Package;
use Mojo::Base 'MirrorCache::WebAPI::Controller::App::Table';

sub index {
    my $c = shift;

    $c->SUPER::admintable('package');
}

sub show {
    my $self = shift;
    my $name = $self->param('name');

    my $f = $self->schema->resultset('Metapkg')->find({name => $name})
        or return $self->reply->not_found;

    my $info = {
        id   => $f->id,
        name => $f->name,
        # dt   => $f->dt,
    };

    return $self->render('app/package/show', package => $info);
}

1;
