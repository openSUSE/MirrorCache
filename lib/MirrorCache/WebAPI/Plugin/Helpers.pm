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

use Mojo::Loader 'load_class';

use MirrorCache::Schema;
use MirrorCache::Events;

my $AUTH_METHOD;
my $AUTH_URL;

my $BRANDING = $ENV{MIRRORCACHE_BRANDING} // '';

sub register {

    my ($self, $app, $args ) = @_;
    my $root  = $args->{root};

    $app->helper( 'mc.rootlocation' => sub {
        shift; # $c
        my $path = shift;
        return $root unless $path;
        return $root . $path if ((substr $path, -1) eq '/');
        return $root . $path . '/';
    });

    $app->helper(
        format_time => sub {
            my ($c, $timedate, $format) = @_;
            return unless $timedate;
            $format ||= "%Y-%m-%d %H:%M:%S %z";
            return $timedate->strftime($format);
        });

    $app->helper(schema => sub { MirrorCache::Schema->singleton });

    $app->helper(mcconfig    => sub { $app->mcconfig });
    $app->helper('mc.config' => sub { $app->mcconfig });
    $app->helper(mcbranding    => sub { $BRANDING });
    $app->helper('mc.branding' => sub { $BRANDING });

    $app->helper(
        # emit_event helper, adds user to events
        emit_event => sub {
            my ($c, $name, $data, $user) = @_;
            die 'Missing event name' unless $name;
            $user //= -1;
            return MirrorCache::Events->singleton->emit($name, [$user, $name, $data]);
        });

    $app->helper(
        icon_url => sub {
            my ($c, $icon) = @_;
            my $icon_asset = $c->app->asset->processed($icon)->[0];
            die "Could not find icon '$icon' in assets" unless $icon_asset;
            return $c->url_for(assetpack => $icon_asset->TO_JSON);
        });

    $app->helper(
        favicon_url => sub {
            my ($c, $suffix) = @_;
            return $c->icon_url("logo$suffix") unless my $job = $c->stash('job');
            my $status = $job->status;
            return $c->icon_url("logo-$status$suffix");
        });

    $app->helper(current_user     => \&_current_user);
    $app->helper(current_username => \&_current_username);
    $app->helper(is_operator      => \&_is_operator);
    $app->helper(is_admin         => \&_is_admin);
    $app->helper(is_local_request => \&_is_local_request);

    $app->helper(is_admin_js         => sub { Mojo::ByteStream->new(shift->helpers->is_admin ? 'true' : 'false') });
    $app->helper(current_username_js => sub { Mojo::ByteStream->new(shift->helpers->current_username) });

    $app->helper(
        # generate popover help button with title and content
        help_popover => sub {
            my ($c, $title, $content, $placement) = @_;
            my $class = 'help_popover fa fa-question-circle';
            my $data = {toggle => 'popover', trigger => 'focus', title => $title, content => $content};
            $data->{placement} = $placement if $placement;
            return $c->t(a => (tabindex => 0, class => $class, role => 'button', (data => $data)));
        });

    $app->helper(
        'auth_method' => sub {
            unless ($AUTH_METHOD) {
                # load auth module
                $AUTH_URL = $ENV{MIRRORCACHE_AUTH_URL};
                # will use default address unless it is set to empty string or other value
                $AUTH_URL = 'https://www.opensuse.org/openid/user/' unless defined($AUTH_URL);
                # we probably can detect method from url when new method is added
                $AUTH_METHOD = $AUTH_URL?  "OpenID" : "Fake";
                my $auth_module = "MirrorCache::Auth::$AUTH_METHOD";
                if (my $err = load_class $auth_module) {
                    $err = 'Module not found' unless ref $err;
                    die "Unable to load auth module $auth_module: $err";
                }
            }
            return $AUTH_METHOD;
        });
    $app->helper(
        'auth_url' => sub {
            shift->auth_method; # make sure it is initialized
            return $AUTH_URL;
        });

    $app->helper(
        include_branding => sub {
            my ($c, $name, %args) = @_;
            if ($BRANDING) {
                my $ret  = $c->render_to_string("branding/$BRANDING/$name");
                return $ret if (defined($ret));
            }
            return $c->render_to_string("branding/default/$name");
        });

    my $trust_addr = $ENV{MIRRORCACHE_TRUST_ADDR};

    if (!$trust_addr) {
        $app->helper( trusted_addr => sub {0} );
    } else {
        my %trust_addr;
        my @addr = split / /, $trust_addr;
        for my $addr (@addr) {
            $trust_addr{$addr} = 1;
            $app->log->warn("Trusting address: $addr");
        }
        $app->helper( trusted_addr => sub { %trust_addr{ shift->tx->original_remote_address } });
    }

    $app->helper(
        'region_name' => sub {
            shift;
            my $input = shift;
            return 'Unknown'       unless $input;
            my $reg = substr($input, 0, 2);
            my $res = 'Unknown';
            $res = 'Oceania'       if $reg eq 'oc';
            $res = 'North America' if $reg eq 'na';
            $res = 'South America' if $reg eq 'sa';
            $res = 'Africa'        if $reg eq 'af';
            $res = 'Europe'        if $reg eq 'eu';
            $res = 'Asia'          if $reg eq 'as';

            return $res . substr($input, 2);

        });

}

sub _current_user {
    my $c = shift;
    # If the value is not in the stash
    my $current_user = $c->stash('current_user');
    if (($current_user || !$current_user->{user}) && $c->trusted_addr) {
        my $user_data = {
            id => -2,
            is_admin => 1,
            is_operator => 1,
            username => 'test_trust_auth',
            nickname => 'test_trust_auth'
        };
        my $user = $c->schema->resultset("Acc")->new_result($user_data);
        $c->stash(current_user => {user => $user});
    }
    elsif (!$current_user || !$current_user->{no_user} || !defined $current_user->{user}) {
        my $id   = $c->session->{user};
        my $user = $id ? $c->schema->resultset("Acc")->find({username => $id}) : undef;
        $c->stash(current_user => $user ? {user => $user} : {no_user => 1});
    }

    $current_user = $c->stash('current_user');
    return $current_user && defined $current_user->{user} ? $current_user->{user} : undef;
}

sub _current_username {
    my $c = shift;

    return '' unless $c->current_user;
    my $current_user = $c->stash('current_user');
    return '' unless $current_user && $current_user->{user};
    return $current_user->{user}->nickname;
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

sub _is_local_request {
    my $c = shift;

    # IPv4 and IPv6 should be treated the same
    my $address = $c->tx->remote_address;
    return $address eq '127.0.0.1' || $address eq '::1';
}

1;
