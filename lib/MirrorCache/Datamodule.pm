# Copyright (C) 2021 SUSE LLC
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

package MirrorCache::Datamodule;
use Mojo::Base -base, -signatures;
use Mojo::URL;
use Digest::SHA qw(sha1_hex);
use MirrorCache::Utils 'region_for_country';

has c => undef, weak => 1;

has [ '_route', '_route_len' ]; # this is '/download'
has [ 'route', 'route_len' ]; # this may be '/download' or empty if one of TOP_FOLDERS present
has [ 'metalink', 'metalink_accept' ];
has [ '_ip', '_country', '_region', '_lat', '_lng' ];
has [ '_avoid_countries' ];
has [ '_pedantic' ];
has [ '_scheme', '_path', '_trailing_slash' ];
has [ '_query', '_query1' ];
has '_original_path';
has '_agent';
has [ '_is_secure', '_is_ipv4', '_is_head' ];
has 'mirrorlist';
has 'json';
has [ 'folder_id', 'file_id' ]; # shortcut to requested folder and file, if known

has root_country => ($ENV{MIRRORCACHE_ROOT_COUNTRY} ? lc($ENV{MIRRORCACHE_ROOT_COUNTRY}) : "");
has '_root_region';
has '_root_longitude' => ($ENV{MIRRORCACHE_ROOT_LONGITUDE} ? int($ENV{MIRRORCACHE_ROOT_LONGITUDE}) : 11);

sub app($self, $app) {
    $self->_route($app->mc->route);
    $self->_route_len(length($self->_route));
    $self->_root_region(region_for_country($self->root_country) || '');
}

sub reset($self, $c, $top_folder = undef) {
    if ($top_folder) {
        $self->route('');
        $self->route_len(0);
    } else {
        $self->route($self->_route);
        $self->route_len($self->_route_len);
    }
    $self->c($c);
    $self->_ip(undef);
}

sub ip_sha1($self) {
    return sha1_hex($self->ip);
}

sub ip($self) {
    unless (defined $self->_ip) {
       $self->_ip($self->c->mmdb->client_ip);
    }
    return $self->_ip;
}

sub region($self) {
    unless (defined $self->_region) {
        $self->_init_location;
    }
    return $self->_region;
}

sub country($self) {
    unless (defined $self->_country) {
        $self->_init_location;
    }
    return $self->_country;
}

sub avoid_countries($self) {
    unless (defined $self->_country) {
        $self->_init_location;
    }
    return $self->_avoid_countries;
}

sub pedantic($self) {
    unless (defined $self->_pedantic) {
        $self->_init_location;
    }
    return $self->_pedantic;
}

sub lat($self) {
    unless (defined $self->_lat) {
        $self->_init_location;
    }
    return $self->_lat;
}

sub lng($self) {
    unless (defined $self->_lng) {
        $self->_init_location;
    }
    return $self->_lng;
}

sub coord($self) {
    unless (defined $self->_lat) {
        $self->_init_location;
    }
    return ($self->_lat, $self->_lng);
}

sub scheme($self) {
    unless (defined $self->_scheme) {
        $self->_init_path;
    }
    return $self->_scheme;
}

sub path($self) {
    unless (defined $self->_path) {
        $self->_init_path;
    }
    return $self->_path, $self->_trailing_slash, $self->_original_path;
}

sub trailing_slash($self) {
    unless (defined $self->_trailing_slash) {
        $self->_init_path;
    }
    return $self->_trailing_slash;
}

sub query($self) {
    unless (defined $self->_query) {
        $self->_init_path;
    }
    return $self->_query;
}

sub query1($self) {
    unless (defined $self->_query1) {
        $self->_init_path;
    }
    return $self->_query1;
}

sub path_query($self) {
    my ($path, $trailing_slash) = $self->path;
    return $path . $trailing_slash . $self->query1;
}

sub original_path($self) {
    unless (defined $self->_trailing_slash) {
        $self->_init_path;
    }
    return $self->_original_path;
}

sub our_path($self, $path) {
    return 1 if 0 eq rindex($path, $self->_route, 0);
    return 0;
}

sub agent($self) {
    unless (defined $self->_agent) {
        $self->_init_headers;
    }
    return $self->_agent;
}

sub is_secure($self) {
    unless (defined $self->_is_secure) {
        $self->_init_req;
    }
    return $self->_is_secure;
}

sub is_ipv4($self) {
    unless (defined $self->_is_ipv4) {
        $self->_init_req;
    }
    return $self->_is_ipv4;
}

sub is_head($self) {
    unless (defined $self->_is_head) {
        $self->_init_req;
    }
    return $self->_is_head;
}

sub redirect($self, $url) {
    return $self->c->redirect_to($url . $self->query1);
}

sub _init_headers($self) {
    my $headers = $self->c->req->headers;
    return unless $headers;
    $self->_agent($headers->user_agent ? $headers->user_agent : '');
    if ($headers->accept && $headers->accept =~ m/\bapplication\/metalink/) {
        $self->metalink(1);
        $self->metalink_accept(1);
    }
}

sub _init_req($self) {
    $self->_is_secure($self->c->req->is_secure? 1 : 0);
    $self->_is_head('HEAD' eq uc($self->c->req->method)? 1 : 0);
    $self->_is_ipv4(1);
    if (my $ip = $self->ip) {
        $self->_is_ipv4(0) if index($ip,':') > -1 && $ip ne '::ffff:127.0.0.1'
    }
}

sub _init_location($self) {
    my ($lat, $lng, $country, $region) = $self->c->mmdb->location($self->ip);
    $self->_lat($lat);
    $self->_lng($lng);
    my $query = $self->c->req->url->query;
    if (my $p = $query->param('COUNTRY')) {
        if (length($p) == 2 ) {
            $country = $p;
            $region = region_for_country($country);
        }
    }
    if (my $p = $query->param('REGION')) {
        if (length($p) == 2 ) {
            $region = lc($p);
        }
    }
    if (my $p = $query->param('AVOID_COUNTRY')) {
        my @avoid_countries = ();
        for my $c (split ',', $p) {
            next unless length($c) == 2;
            $c = lc($c);
            push @avoid_countries, $c;
            $country = '' if $c eq lc($country);
        }
        $self->_avoid_countries(\@avoid_countries);
    }
    $country = substr($country, 0, 2) if $country;
    $self->_country($country // '');
    $self->_region($region // '');

    my $pedantic;
    if(my $p = $query->param('PEDANTIC')) {
        $pedantic = $p;
    } else {
        $pedantic = $ENV{'MIRRORCACHE_PEDANTIC'};
    }
    $self->_pedantic($pedantic // 0);
}

sub _init_path($self) {
    my $url = $self->c->req->url->to_abs;
    $self->_scheme($url->scheme);
    if ($url->query) {
        $self->_query($url->query);
        $self->_query1('?' . $url->query);
        $self->mirrorlist(1) if defined $url->query->param('mirrorlist');
        $self->json(1)       if defined $url->query->param('json');
    } else {
        $self->_query('');
        $self->_query1('');
    }

    my $reqpath = $url->path;
    my $path = Mojo::Util::url_unescape(substr($reqpath, $self->route_len));
    $path = '/' unless $path;

    my $trailing_slash = '';
    if($path ne '/' && '/' eq substr($path, -1)) {
        $trailing_slash = '/';
        $path = substr($path, 0, -1);
    }
    $self->_original_path($path);
    my @c = reverse split m@/@, $path;
    my @c_new;
    while (@c) {
        my $component = shift @c;
        next unless length($component);
        if ($component eq '.') { next; }
        if ($component eq '..') { shift @c; next }
        push @c_new, $component;
    }
    $path = '/'.join('/', reverse @c_new);
    if(!$trailing_slash && ((my $pos = length($path)-length('.metalink')) > 1)) {
        if ('.metalink' eq substr($path,$pos)) {
            $self->metalink(1);
            $path = substr($path,0,$pos);
        }
    }
    if (!$trailing_slash && ((my $pos = length($path) - length('.mirrorlist')) > 1)) {
        if ('.mirrorlist' eq substr($path, $pos)) {
            $self->mirrorlist(1);
            $path = substr($path, 0, $pos);
        }
    }
    $self->_path($path);
    $self->_trailing_slash($trailing_slash);
    $self->agent; # parse headers
}

sub root_is_hit($self) {
    return 1 if $self->_root_region && $self->_root_region eq $self->region;
    return 0;
}

sub root_is_better($self, $region, $lng) {
    if ($self->_root_region && $region && $self->lng && $self->_root_longitude && $region eq $self->_root_region) {
        # simly check if root is closer to the client by longitude
        return 1 if abs( $self->_root_longitude - $self->lng ) < abs( $lng - $self->lng );
    }
    return 0;
}

1;
