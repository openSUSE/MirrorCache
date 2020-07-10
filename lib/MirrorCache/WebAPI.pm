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
use MaxMind::DB::Reader;

use Mojolicious::Commands;

# This method will run once at server start
sub startup {
    my $self = shift;
    my $root = $ENV{MIRRORCACHE_ROOT};
    my $city_mmdb = $ENV{MIRRORCACHE_CITY_MMDB};

    die("MIRRORCACHE_ROOT is not set") unless $root;
    die("MIRRORCACHE_CITY_MMDB is not set") unless $city_mmdb;
    die("MIRRORCACHE_CITY_MMDB is not a file ($city_mmdb)") unless -f $city_mmdb;
    my $reader = MaxMind::DB::Reader->new( file => $city_mmdb );

    # take care of DB deployment or migration before starting the main app
    MirrorCache::Schema->singleton;

    push @{$self->commands->namespaces}, 'MirrorCache::WebAPI::Command';

    $self->plugin('DefaultHelpers');
    $self->plugin('RenderFile');
    $self->plugin('ClientIP');

    push @{$self->plugins->namespaces}, 'MirrorCache::WebAPI::Plugin';

    $self->plugin('Helpers', root => $root, route => '/download');
    # check prefix
    if (-1 == rindex $root, 'http', 0) {
        die("MIRRORCACHE_ROOT is not a directory ($root)") unless -d $root;
        $self->plugin('RootLocal');
    } else {
        $self->plugin('RootRemote');
    }

    $self->plugin('Mmdb', $reader);
    $self->plugin('Backstage');
    $self->plugin('AuditLog');
    $self->plugin('Dir');
    $self->plugin('RenderFileFromMirror');
}

sub schema { MirrorCache::Schema->singleton }

sub run { __PACKAGE__->new->start }

1;
