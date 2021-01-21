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

use Mojo::URL;

use MirrorCache::Schema;
use MirrorCache::Events;

sub register {

    my ($self, $app, $args ) = @_;
    my $root  = $args->{root};
    my $route = $args->{route};
    
    $app->helper( 'mc.rootlocation' => sub {
        shift; # $c
        my $path = shift;
        return $root unless $path;
        return $root . $path if ((substr $path, -1) eq '/');
        return $root . $path . '/';
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

    $app->helper(current_user     => \&_current_user);
    $app->helper(is_operator      => \&_is_operator);
    $app->helper(is_admin         => \&_is_admin);

    $app->helper(is_admin_js    => sub { Mojo::ByteStream->new(shift->helpers->is_admin    ? 'true' : 'false') });

    my %subsidiary_urls;
    my @subsidiaries;
    eval { #the table may be missing - no big deal 
        @subsidiaries = $app->schema->resultset('Subsidiary')->all;
    };
    for my $s (@subsidiaries) {
        my $url = $s->hostname;
        $url = "http://" . $url unless 'http' eq substr($url, 0, 4);
        $url = $url . $s->uri if $s->uri;
        $subsidiary_urls{lc($s->region)} = Mojo::URL->new($url)->to_abs;
    }

    $app->helper(
        has_subsidiary => sub {
            return undef unless keys %subsidiary_urls;
            my $c = shift;
            my ($region, $country) = $c->mmdb->region;
            return ($subsidiary_urls{$region}->clone(), $country);
        });
}

sub _current_user {
    my $c = shift;

    # If the value is not in the stash
    my $current_user = $c->stash('current_user');
    unless ($current_user && ($current_user->{no_user} || defined $current_user->{user})) {
        my $id   = $c->session->{user};
        my $user = $id ? $c->schema->resultset("Acc")->find({username => $id}) : undef;
        $c->stash(current_user => $current_user = $user ? {user => $user} : {no_user => 1});
    }

    return $current_user && defined $current_user->{user} ? $current_user->{user} : undef;
}

sub _is_operator {
    my $c    = shift;
    my $user = shift || $c->current_user;

    return ($user && $user->is_operator);
}

sub _is_admin {
    my $c    = shift;
    my $user = shift || $c->current_user;

    return ($user && $user->is_admin);
}


1;
