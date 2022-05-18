# Copyright (C) 2021,2022 SUSE LLC
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
use Time::HiRes qw(time);
use Digest::SHA qw(sha1_hex);
use Mojolicious::Types;
use MirrorCache::Utils 'region_for_country';

has c => undef, weak => 1;

has [ '_route', '_route_len' ]; # this is '/download'
has [ 'route', 'route_len' ]; # this may be '/download' or empty if one of TOP_FOLDERS present
has [ 'metalink', 'metalink_accept' ];
has [ '_ip', '_country', '_region', '_lat', '_lng', '_vpn' ];
has [ '_avoid_countries' ];
has [ '_pedantic' ];
has [ '_scheme', '_path', '_trailing_slash' ];
has [ '_query', '_query1' ];
has '_original_path';
has 'must_render_from_root';
has '_agent';
has [ '_is_secure', '_is_ipv4', '_ipvstrict', '_is_head' ];
has 'mirrorlist';
has 'zsync';
has 'json';
has [ 'folder_id', 'file_id', 'file_age', 'folder_sync_last', 'folder_scan_last' ]; # shortcut to requested folder and file, if known

has root_country => ($ENV{MIRRORCACHE_ROOT_COUNTRY} ? lc($ENV{MIRRORCACHE_ROOT_COUNTRY}) : "");
has '_root_region';
has '_root_longitude' => ($ENV{MIRRORCACHE_ROOT_LONGITUDE} ? int($ENV{MIRRORCACHE_ROOT_LONGITUDE}) : 11);

has root_subtree => ($ENV{MIRRORCACHE_SUBTREE} // "");

has _vpn_var => $ENV{MIRRORCACHE_VPN};
has vpn_prefix => ($ENV{MIRRORCACHE_VPN_PREFIX} ? lc($ENV{MIRRORCACHE_VPN_PREFIX}) : "10.");

has 'at';
has '_mime';

my $TYPES = Mojolicious::Types->new;

sub elapsed($self) {
    return abs(time - $self->at);
}

sub app($self, $app) {
    $self->_route($app->mc->route);
    $self->_route_len(length($self->_route));
    $self->_root_region(region_for_country($self->root_country) || '');
}

sub reset($self, $c, $top_folder = undef) {
    $self->at(time);
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
        $self->_ip($self->c->geodb->client_ip);
    }
    return $self->_ip;
}

sub vpn($self) {
    return $self->_vpn_var if defined $self->_vpn_var;

    unless (defined $self->_vpn) {
        my $ip = $self->ip;
        $ip =~ s/^::ffff://;
        if ($self->vpn_prefix && (rindex($ip, $self->vpn_prefix, 0) == 0)) {
            $self->_vpn(1);
        } else {
            $self->_vpn(0);
        }
    }
    return $self->_vpn;
}

sub extra($self) {
    return ($self->metalink || $self->mirrorlist || $self->zsync);
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

sub mime($self) {
    unless (defined $self->_mime) {
        $self->_init_path;
    }
    return $self->_mime;
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

sub ipv($self) {
    return "ipv4" if $self->is_ipv4;
    return "ipv6";
}

sub ipvstrict($self) {
    unless (defined $self->_ipvstrict) {
        $self->_init_req;
    }
    return $self->_ipvstrict;
}

sub is_head($self) {
    unless (defined $self->_is_head) {
        $self->_init_req;
    }
    return $self->_is_head;
}

sub redirect($self, $url) {
    my $xtra = '';
    if ($self->_original_path =~ m/.*\.metalink$/) {
        $xtra = ".metalink";
    } elsif ($self->_original_path =~ m/.*\.mirrorlist$/) {
        $xtra = ".mirrorlist";
    }

    return $self->c->redirect_to($url . $xtra . $self->query1);
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
    $self->_ipvstrict(0);
    my $query = $self->c->req->url->query;
    my $p;
    $p = $query->every_param('IPV');
    if (scalar(@$p) && $p->[-1] ne '0') {
        $self->_ipvstrict(1);
    }
    $p = $query->every_param('IPV4');
    if (scalar(@$p) && $p->[-1] ne '0') {
        $self->_is_ipv4(1);
        $self->_ipvstrict(1);
    }
    $p = $query->every_param('IPV6');
    if (scalar(@$p) && $p->[-1] ne '0') {
        $self->_is_ipv4(0);
        $self->_ipvstrict(1);
    }
    unless (defined $self->_is_ipv4) {
        $self->_is_ipv4(1);
        if (my $ip = $self->ip) {
            $ip =~ s/^::ffff://;
            $self->_is_ipv4(0) if index($ip,':') > -1;
        }
    }
}

sub _init_location($self) {
    my ($lat, $lng, $country, $region) = $self->c->geodb->location($self->ip);
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
            $country = '' if $c eq lc($country // '');
        }
        $self->_avoid_countries(\@avoid_countries);
    }
    $country = substr($country, 0, 2) if $country;
    $self->_country($country // '');
    $self->_region($region // '');
}

sub _init_path($self) {
    my $url = $self->c->req->url->to_abs;
    $self->_scheme($url->scheme);
    if ($self->c->req->is_secure) {
        $self->_scheme('https');
    }
    my $pedantic;
    my $query = $url->query;
    if (my $query_string = $url->query->to_string) {
        $self->_query($query);
        $self->_query1('?' . $query_string);
        $self->mirrorlist(1) if defined $query->param('mirrorlist');
        $self->zsync(1)      if defined $query->param('zsync');
        $self->json(1)       if defined $query->param('json') || defined $query->param('JSON');
        $pedantic = $query->param('PEDANTIC');
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
    if (!$trailing_slash && ((my $pos = length($path) - length('.zsync')) > 1)) {
        if ('.zsync' eq substr($path, $pos)) {
            $self->zsync(1);
            $path = substr($path, 0, $pos);
        }
    }
    $pedantic = $ENV{'MIRRORCACHE_PEDANTIC'} unless defined $pedantic;
    if (!defined $pedantic) {
        if ( $path =~ m/.*\/([^\/]*-Current[^\/]*)$/ ) {
            $pedantic = 1;
        } else {
            my $path_without_common_digit_patterns = $path =~ s/(Leap-\d\d\.\d|x86_64|s390x|ppc64|aarch64|E20|sha256(\.asc)?$)\b//gr;
            $pedantic = 1 if $path_without_common_digit_patterns !~ m/.*\/([^\/]*\d\.?\d[^\/]*)$/;
        }
    }

    $self->_pedantic($pedantic) if defined $pedantic;

    $self->must_render_from_root(1)
        if !$self->mirrorlist
        && ( !$self->metalink || $self->metalink_accept )
        && !$self->zsync
        && $path =~ m/.*\/(repodata\/repomd.xml[^\/]*|media\.1\/media|.*\.sha256(\.asc)|Release(.key|.gpg)?|InRelease|Packages(.gz)?|Sources(.gz)?|.*_Arch\.(files|db|key)(\.(sig|tar\.gz(\.sig)?))?|(files|primary|other).xml.gz|[Pp]ackages(\.[A-Z][A-Z])?\.(xz|gz)|gpg-pubkey.*\.asc|CHECKSUMS)$/;

    my ($ext) = $path =~ /([^.]+)$/;
    my $mime = '';
    $mime = $TYPES->type($ext) // '' if $ext;
    $self->_mime($mime);
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

my $RECKLESS=int($ENV{MIRRORCACHE_RECKLESS} // 0);

sub sync_last_ago($self) {
    return 30*24*60*60 if $RECKLESS;
    my $sync_last = $self->folder_sync_last;
    return 0 unless $sync_last;
    $sync_last->set_time_zone('local');
    return time() - $sync_last->epoch;
}

sub scan_last_ago($self) {
    return 30*24*60*60 if $RECKLESS;
    my $scan_last = $self->folder_scan_last;
    return 0 unless $scan_last;
    $scan_last->set_time_zone('local');
    return time() - $scan_last->epoch;
}

1;
