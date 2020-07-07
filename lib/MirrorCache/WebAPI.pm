# Copyright (C) 2020 SUSE LLC
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

package MirrorCache::WebAPI;
use Mojo::Base 'Mojolicious';


use MirrorCache::Schema;
# use MirrorCache::WebAPI::Plugin::Helpers;
# use MirrorCache::Log 'setup_log';
# use MirrorCache::Setup;

use Mojolicious::Commands;

# This method will run once at server start
sub startup {
    my $self = shift;
    my $root = $ENV{MIRRORCACHE_ROOT};

    die("MIRRORCACHE_ROOT is not set") unless $root;
    die("MIRRORCACHE_ROOT has incorrect value") unless -d $root;

    # "templates/webapi" prefix
    # $self->renderer->paths->[0] = path($self->renderer->paths->[0])->child('webapi')->to_string;

    # MirrorCache::Setup::read_config($self);
    # setup_log($self);
    # MirrorCache::Setup::setup_app_defaults($self);
    # MirrorCache::Setup::setup_mojo_tmpdir();
    # MirrorCache::Setup::add_build_tx_time_header($self);

    # take care of DB deployment or migration before starting the main app
    MirrorCache::Schema->singleton;

    # register basic routes
    # my $r         = $self->routes;

    # register routes
    # $r->get('/download')-a>to('directory#download');

    push @{$self->commands->namespaces}, 'MirrorCache::WebAPI::Command';

    $self->plugin('DefaultHelpers');
    $self->plugin('RenderFile');
    push @{$self->plugins->namespaces}, 'MirrorCache::WebAPI::Plugin';

    $self->plugin('Helpers', root => $root, route => '/download');
    $self->plugin('Backstage');
    $self->plugin('AuditLog');
    $self->plugin('Dir', root => $root, route => '/download');
    $self->plugin('RenderFileFromMirror', root => $root);
}

sub schema { MirrorCache::Schema->singleton }

sub run { __PACKAGE__->new->start }

1;
