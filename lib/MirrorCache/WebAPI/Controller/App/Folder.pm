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

package MirrorCache::WebAPI::Controller::App::Folder;
use Mojo::Base 'MirrorCache::WebAPI::Controller::App::Table';

sub index {
    shift->SUPER::admintable('folder');
}

sub show {
    my $self = shift;
    my $id = $self->param('id');

    my $f = $self->schema->resultset('Folder')->find($id)
        or return $self->reply->not_found;

    my $info = {
        id                  => $f->id,
        path                => $f->path,
        db_sync_last        => $f->db_sync_last,
        db_sync_scheduled   => $f->db_sync_scheduled,
        db_sync_priority    => $f->db_sync_priority,
        db_sync_for_country => $f->db_sync_for_country,
    };

    # for my $x ($f->files->all) {
    #    $info->{files}->{$x->key} = $x->value;
    # }
    
    return $self->render('app/folder/show', folder => $info);
}

1;
