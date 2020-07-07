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
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

package MirrorCache::WebAPI::Plugin::Helpers;
use Mojo::Base 'Mojolicious::Plugin';

use MirrorCache::Schema;
use MirrorCache::Events;

sub register {

    my ($self, $app, $args ) = @_;
    my $root  = $args->{root};
    my $route = $args->{route};
    
    $app->helper( 'mc.root' => sub {
        shift; # $c
        my $path = shift;
        return $root unless $path;
        return $root . $path;
    });
    $app->helper( 'mc.route' => sub { $route });

    $app->helper(
        format_time => sub {
            my ($c, $timedate, $format) = @_;
            return unless $timedate;
            $format ||= "%Y-%m-%d %H:%M:%S %z";
            return $timedate->strftime($format);
        });

    $app->helper(schema => sub { MirrorCache::Schema->singleton });

    $app->helper(
        # emit_event helper, adds user to events
        emit_event => sub {
            my ($self, $name, $data, $tag) = @_;
            die 'Missing event name' unless $name;
            my $user = 0; # TBD
            return MirrorCache::Events->singleton->emit($name, [$user, $name, $data, $tag]);
        });
}

1;
