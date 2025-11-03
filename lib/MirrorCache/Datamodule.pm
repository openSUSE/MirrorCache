# Copyright (C) 2021-2025 SUSE LLC
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
use Mojo::Util qw(url_unescape);
use Time::HiRes qw(time);
use Digest::SHA qw(sha1_hex);
use Mojolicious::Types;
use MirrorCache::Utils 'region_for_country';

use Directory::Scanner::OBSMediaVersion;

my $MCDEBUG = $ENV{MCDEBUG_DATAMODULE} // $ENV{MCDEBUG_ALL} // 0;

has c => undef, weak => 1;

my @ROUTES = ( '/browse', '/download' );
has [ '_route', '_route_len' ]; # this is '/download' or '/browse'
has [ 'route', 'route_len' ]; # this may be '/download' or '/browse' or empty if one of TOP_FOLDERS present
has [ 'metalink', 'meta4', 'zsync', 'accept_all', 'accept_metalink', 'accept_meta4', 'accept_zsync' ];
has 'xtra';
has metalink_limit => 10;          # maximum mirrors to search for metalink
has [ '_ip', '_country', '_region', '_lat', '_lng', '_vpn' ];
has [ '_avoid_countries' ];
has [ '_pedantic' ];
has [ '_glob' ];           # glob pattern from url for folder rendering, e.g. "file*.iso"
has [ '_glob_regex' ];     # generated regex for _glob, i.e. "^file.*\.iso$"
has [ '_regex' ];          # regex from url for folder rendering, e.g. "file.*iso"
has [ '_scheme', '_path', '_trailing_slash', 'ext' ];
has [ '_query', '_query1' ];
has '_original_path';
has 'must_render_from_root';
has '_agent';
has '_browser';
has [ '_is_secure', '_is_ipv4', '_ipvstrict', '_is_head' ];
has 'mirrorlist';
has [ 'torrent', 'magnet', 'btih' ];
has [ 'json', 'jsontable' ];
has [ 'folder_id', 'file_id', 'file_age', 'folder_sync_last', 'folder_scan_last', 'folder_sync_requested' ]; # shortcut to requested folder and file, if known
has [ 'file_size', 'file_mtime' ];
has [ 'media_version' ];
has [ 'real_folder_id' ];

has root_country => ($ENV{MIRRORCACHE_ROOT_COUNTRY} ? lc($ENV{MIRRORCACHE_ROOT_COUNTRY}) : "");
has '_root_region';
has '_root_longitude' => ($ENV{MIRRORCACHE_ROOT_LONGITUDE} ? int($ENV{MIRRORCACHE_ROOT_LONGITUDE}) : 11);

has root_subtree => ($ENV{MIRRORCACHE_SUBTREE} // "");

has _vpn_var => $ENV{MIRRORCACHE_VPN};
has _vpn_header_variable => ($ENV{MIRRORCACHE_VPN_HEADER_VARIABLE} // "");
has _vpn_header_value    => ($ENV{MIRRORCACHE_VPN_HEADER_VALUE} // "");
has vpn_prefix => ($ENV{MIRRORCACHE_VPN_PREFIX} ? lc($ENV{MIRRORCACHE_VPN_PREFIX}) : "10.");
has vpn_prefix_neg => ($ENV{MIRRORCACHE_VPN_PREFIX_NEG} ? lc($ENV{MIRRORCACHE_VPN_PREFIX_NEG}) : "");

has 'at';
has '_mime';
has 'mirror_country';

my $TYPES = Mojolicious::Types->new;

sub elapsed($self) {
    return abs(time - $self->at);
}

sub app($self, $app) {
    eval {
        if (my $prefix = $app->mcconfig->vpn_prefix) {
            $self->vpn_prefix($prefix);
        }
    };
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
    $self->accept_all(undef);
    $self->accept_meta4(undef);
    $self->accept_metalink(undef);
    $self->accept_zsync(undef);
    $self->metalink(undef);
    $self->meta4(undef);
    $self->zsync(undef);
    $self->mirrorlist(undef);
    $self->torrent(undef);
    $self->magnet(undef);
    $self->btih(undef);
    $self->xtra(undef);
    $self->file_id(undef);
    $self->file_size(undef);
    $self->file_mtime(undef);
    $self->file_age(undef);
    $self->media_version(undef);
    $self->ext(undef);
    $self->_vpn(undef);
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
    if (my $var = $self->_vpn_header_variable) {
        unless (defined $self->_vpn) {
            if (my $val = scalar($self->_vpn_header_value)) {
                eval {
                    if (my $zone = $self->c->req->headers->header($var)) {
                        if (fc($zone) eq fc($val)) {
                            $self->_vpn(1);
                        } else {
                            $self->_vpn(0);
                        }
                    }
                    1;
                } or print STDERR "Error in detecting $var: $@";
            }
        }
    }

    unless (defined $self->_vpn) {
        unless ($self->vpn_prefix) {
            $self->_vpn(0);
        } else {
            my $ip = $self->ip;
            $ip =~ s/^::ffff://;
            my $match = 0;
            for my $pref (split /[\s]+/, $self->vpn_prefix) {
                $match = 1 if (rindex($ip, $pref, 0) == 0);
            }
            if ($match && $self->vpn_prefix_neg) {
                for my $pref (split /[\s]+/, $self->vpn_prefix_neg) {
                    $match = 0 if (rindex($ip, $pref, 0) == 0);
                }
            } 
            $self->_vpn($match);
        }
    }
    return $self->_vpn;
}

sub extra($self) {
    return ($self->metalink || $self->meta4 || $self->mirrorlist || $self->zsync || $self->magnet || $self->torrent || $self->btih );
}

sub region($self) {
    unless (defined $self->_lat) {
        $self->_init_location;
    }
    return $self->_region;
}

sub country($self) {
    unless (defined $self->_lat) {
        $self->_init_location;
    }
    return $self->_country;
}

sub avoid_countries($self) {
    unless (defined $self->_lat) {
        $self->_init_location;
    }
    return $self->_avoid_countries;
}

sub pedantic($self) {
    unless (defined $self->_pedantic) {
        $self->_init_path;
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

sub glob($self) {
    my $p = $self->_glob;
    return $p if defined $p;

    $self->_init_path;
    return $self->_glob;
}

sub glob_regex($self) {
    my $p = $self->_glob_regex;
    return $p if defined $p;

    $self->_init_path;
    return $self->_glob_regex;
}

sub regex($self) {
    my $p = $self->_regex;
    return $p if defined $p;

    $self->_init_path;
    return $self->_regex;
}

sub re_pattern($self) {
    my ($regex, $glob) = ($self->regex, $self->glob);

    my $res = '';
    if ($regex) {
        $res = "REGEX=$regex";
    } elsif ($glob) {
        $res = "P=$glob";
    }
    return $res;
}

sub our_path($self, $path) {
    for my $r (@ROUTES) {
        next unless 0 eq rindex($path, $r, 0);
        $self->_route($r);
        $self->_route_len(length($r));
        $self->route($r);
        $self->route_len(length($r));
        return 1;
    }
    return 0;
}

sub agent($self) {
    unless (defined $self->_agent) {
        $self->_init_headers;
    }
    return $self->_agent;
}

sub browse($self) {
    return 1 if ($self->route && $self->route eq '/browse') || (!$self->route && $self->browser);
    return 0;
}


sub browser($self) {
    unless (defined $self->_browser) {
        $self->_init_headers;
    }
    return $self->_browser;
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

sub redirect($self, $url, $skip_xtra = undef) {
    my $xtra = '';

    my $c = $self->c;
    my $param = $c->req->params;
    if (!$skip_xtra && $self->_original_path =~ m/(\.metalink|\.meta4|\.zsync|\.mirrorlist|\.torrent|\.magnet|\.btih)$/) {
        $xtra = $1;
        $url = $url . $xtra;
    }
    if (my $version = Directory::Scanner::OBSMediaVersion::parse_version($url)) {
        $c->res->headers->add('X-MEDIA-VERSION' => $version);
    }
    return $c->redirect_to($url) unless $param->to_hash;
    return $c->redirect_to($url . '?' . $param->to_string);
}

sub accept($self) {
    return $self->accept_metalink || $self->accept_meta4 || $self->accept_zsync;
}

sub _init_headers($self) {
    $self->_agent('');
    $self->_browser('');
    my $headers = $self->c->req->headers;
    $self->c->log->error($self->c->dumper("DATAMODULE HEADERS", $headers)) if $MCDEBUG;
    return unless $headers;
    if (my $agent = $headers->user_agent) {
        $self->_agent($agent);
        if ($agent =~ $self->c->mcconfig->browser_agent_mask) {
            $self->_browser($1) if $1;
            unless ($self->_route) {
                $self->_route('/browse');
                $self->_route_len(length('/browse'));
            }
        }
    }
    my ($region, $country, $metalink_limit);
    for my $name (@{$headers->names}) {
        next unless $name;
        $name = lc($name);
        if ($name eq 'region-code' || $name eq 'x-region-code' || $name eq 'x-geo-region-code') {
            $region = $headers->header($name);
            $region = lc(substr $region, 0, 2) if $region;
        }
        if ($name eq 'country-code' || $name eq 'x-country-code' || $name eq 'x-geo-country-code') {
            $country = $headers->header($name);
            if ($country) {
                $country = lc(substr $country, 0, 2);
                $region = region_for_country($country) unless $region;
            }
        }
        if ($name eq 'x-metalink-limit') {
            $metalink_limit = $headers->header($name);
            $self->metalink_limit($metalink_limit) if int($metalink_limit) > 0;
        }
    }
    $self->_country($country) if $country;
    $self->_region($region)   if $region;

    $self->c->log->error($self->c->dumper("DATAMODULE HEADERS ACCEPT", $headers->accept)) if $MCDEBUG;
    return unless $headers->accept;

    for my $xtra (qw(metalink meta4 zsync)) {
        my $x = $xtra;
        $x = 'x-zsync'   if $x eq 'zsync';
        $x = 'metalink4' if $x eq 'meta4';
        if ($headers->accept =~ m/\bapplication\/$x/i) {
            my $method = "accept_$xtra";
            $self->$method(1);
            $self->$xtra(1);
            $self->xtra($xtra);
        }
    }
    $self->accept_all(1) if scalar($headers->accept =~ m/\*\/\*/) && scalar($headers->accept ne '*/*');
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
    my $query = $self->c->req->url->query;
    if (my $p = $query->param('IP')) {
        $self->_ip($p);
    }
    my ($lat, $lng, $country, $region) = $self->c->geodb->location($self->ip);
    $region = 'eu' if $country && $country eq 'tr';
    $self->_lat($lat);
    $self->_lng($lng);
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
    if (!$country) {
        $country = '';
    } else {
        $country = substr(lc($country), 0, 2) ;
    }
    my $p = $query->param('AVOID_COUNTRY');
    my @avoid_countries = ();
    @avoid_countries = ('by', 'ru') if $country eq 'ua';
    if ($p) {
        for my $c (split ',', $p) {
            next unless length($c) == 2;
            $c = lc($c);
            push @avoid_countries, $c;
            $country = '' if $c eq lc($country // '');
        };
    }
    $self->_avoid_countries(\@avoid_countries);

    $self->_country($country) unless $self->_country;
    $self->_region($region // '') unless $self->_region;
    if (my $p = $query->param('LIMIT')) {
        # check numeric value
        if (int($p) > 0)  {
            $self->metalink_limit($p);
        }
    }
}

sub _glob2re {
    my $globstr = shift;
    my %patmap = (
        '*' => '.*',
        '?' => '.',
        '[' => '[',
        ']' => ']',
    );
    $globstr =~ s{(.)} { $patmap{$1} || "\Q$1" }ge;
    return '^' . $globstr . '$';
}

sub _init_path($self) {
    my $url = $self->c->req->url->to_abs;
    $self->_scheme($url->scheme);
    if ($self->c->req->is_secure) {
        $self->_scheme('https');
    }
    my ($pedantic, $glob, $glob_regex, $regex);
    my $query = $url->query;
    if (my $query_string = $query->to_string) {
        $self->_query($query);
        $self->_query1('?' . $query_string);
        $self->mirrorlist(1) if defined $query->param('mirrorlist');
        $self->meta4(1)      if defined $query->param('meta4');
        $self->metalink(1)   if defined $query->param('metalink');
        $self->zsync(1)      if defined $query->param('zsync');
        $self->torrent(1)    if defined $query->param('torrent');
        $self->magnet(1)     if defined $query->param('magnet');
        $self->btih(1)       if defined $query->param('btih');
        $self->json(1)       if defined $query->param('json') || defined $query->param('JSON');
        $self->json(1)       if defined $query->param('jsontable');
        $self->jsontable(1)  if defined $query->param('jsontable');
        $pedantic = $query->param('PEDANTIC');
        my $pairs = $query->pairs;
        my @pairs = @$pairs;
        while (@pairs) {
            my $k = shift @pairs;
            last unless defined $k;
            my $v = shift @pairs;
            next unless $v;
            if ($k eq 'REGEX') {
                $regex = $v if eval { m/$v/; 1; };
            } elsif ($k eq 'P' || $k eq 'GLOB') {
                my $x = _glob2re($v);
                next unless ($x && eval { m/$x/; 1; });
                $glob  = $v;
                $glob_regex = $x;
            }
        }

    } else {
        $self->_query('');
        $self->_query1('');
    }

    $self->_regex     ($regex // '');
    $self->_glob      ($glob // '');
    $self->_glob_regex($glob_regex // '');

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
    unless ($trailing_slash || $self->extra) {
        my @ext = qw(metalink meta4 mirrorlist zsync torrent magnet btih);
        for my $ext (@ext) {
            if((my $pos = length($path)-length(".$ext")) > 1) {
                if (".$ext" eq substr($path,$pos)) {
                    $self->$ext(1);
                    $path = substr($path,0,$pos);
                    last;
                }
            }
        }
    }

    $pedantic = $ENV{'MIRRORCACHE_PEDANTIC'} unless defined $pedantic;
    if (!defined $pedantic) {
        if ( $path =~ m/.*\/([^\/]*-Current[^\/]*)$/ ) {
            $pedantic = 1;
        } else {
            my $path_without_common_digit_patterns = $path =~ s/(Leap-\d\d\.\d|x86_64|s390x|ppc64|aarch64|E20|sha\d\d\d(\.asc)?$)\b//gr;
            $pedantic = 1 if $path_without_common_digit_patterns !~ m/.*\/([^\/]*\d\.?\d[^\/]*)$/;
        }
    }

    $self->_pedantic($pedantic // 0);

    $self->agent; # parse headers
    if (
        ( $self->accept_all || !$self->extra )
        && $self->_original_path eq $path
        && $path =~ m/\/(repodata\/repomd\.xml[^\/]*|media\.1\/(media|products)|content|.*\.sha\d\d\d(\.asc)?|Release(\.key|\.gpg)?|InRelease|Packages(\.gz|\.zst)?|Sources(\.gz|\.zst)?|.*_Arch\.(files|db|key)(\.(sig|tar\.gz(\.sig)?|tar\.zst(\.sig)?))?|(files|primary|other)\.xml\.(gz|zck|zst)|[Pp]ackages(\.[A-Z][A-Z])?\.(xz|gz|zst)|gpg-pubkey.*\.asc|CHECKSUMS(\.asc)?|APKINDEX\.tar\.gz)$/
    ) {
        $self->must_render_from_root(1);

        my $stale_time = 0xff >> 2;  # allow caches to serve content for ~1 minute while they re-check
        my $max_age = $stale_time + (~time() & 0xff); # for how long to consider the content valid

        $self->c->res->headers->cache_control("public, max-age=$max_age stale-while-revalidate=$stale_time stale-if-error=86400");
    }

    my ($ext) = $path =~ /([^.]+)$/;
    $self->ext($ext) if $ext;
    my $mime = '';
    $mime = $TYPES->type($ext) // '' if $ext;
    $self->_mime($mime);
    $self->_path(url_unescape($path));
    $self->_trailing_slash($trailing_slash);
}

sub root_is_hit($self) {
    return 1 if $self->_root_region && $self->_root_region eq $self->region;
    return 0;
}

sub root_is_better($self, $region, $lng) {
    if ($self->_root_region && $region && $self->lng && $self->_root_longitude && $region eq $self->_root_region) {
        # simly check if root is closer to the client by longitude
        return 1 unless defined $lng;
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

sub set_file_stats($self, $id, $size, $mtime, $age, $name) {
    $self->file_id($id);
    $self->file_size($size);
    $self->file_mtime($mtime);
    $self->file_age($age);

    return unless $name;
    if (my $version = Directory::Scanner::OBSMediaVersion::parse_version($name)) {
        $self->media_version($version);
    }
}

sub etag($self) {
    my $size  = sprintf('%X', $self->file_size  // 0);
    my $mtime = sprintf('%X', $self->file_mtime // 0);
    my $res = "$mtime-$size";
    my $xtra;
    if ($self->_original_path =~ m/\.(metalink|meta4|zsync|mirrorlist|torrent|magnet|btih)$/) {
        $xtra = $1;
    } else {
        $xtra = $self->xtra;
    }
    $res = "$res-$xtra" if $xtra;
    return $res;
}

1;
