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

package MirrorCache::WebAPI::Controller::Report::Download;
use Mojo::Base 'Mojolicious::Controller';

sub index {
    my ($self, $template) = @_;
    my $group = $self->req->param('group');
    my $params = $self->req->params->to_string;

    $self->stash;
    $self->render(
        "report/download/index",
        column      => $group,
        params      => $params,
    );
}

1;
