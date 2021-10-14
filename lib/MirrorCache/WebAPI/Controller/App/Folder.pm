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

use File::Basename;

sub index {
    shift->SUPER::admintable('folder');
}

sub show {
    my $self = shift;
    my $id = $self->param('id');

    my $f = $self->schema->resultset('Folder')->find($id)
        or return $self->reply->not_found;

    my $info = {
        id             => $f->id,
        path           => $f->path,
        wanted         => $f->wanted,
        sync_last      => $f->sync_last,
        sync_scheduled => $f->sync_scheduled,
        sync_requested => $f->sync_requested,
        scan_last      => $f->scan_last,
        scan_scheduled => $f->scan_scheduled,
        scan_requested => $f->scan_requested,
    };

    my $parent_path = dirname($f->path);

    return $self->render('app/folder/show', folder => $info, parent_path => $parent_path);
}

1;
