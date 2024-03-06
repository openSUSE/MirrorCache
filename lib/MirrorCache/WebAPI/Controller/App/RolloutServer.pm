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

package MirrorCache::WebAPI::Controller::App::RolloutServer;
use Mojo::Base 'MirrorCache::WebAPI::Controller::App::Table';

sub index {
    my $c = shift;
    my $version = $c->param('version');
    return $c->render(code => 400, text => "Mandatory argument is missing") unless $version;

    $c->stash( version => $version );
    $c->SUPER::admintable('rollout_server');
}

1;
