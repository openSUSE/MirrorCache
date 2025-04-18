# Copyright (C) 2020,2021 SUSE LLC
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

package MirrorCache::WebAPI::Plugin::RootRemote;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::Util ('trim');
use Encode ();
use Mojo::JSON qw(decode_json);
use URI::Escape ('uri_unescape');
use File::Basename;
use HTML::Parser;
use Time::Piece;

use Directory::Scanner::OBSMediaVersion;

# rooturlredirect as defined in mcconfig->redirect
# rooturlsredirect same as above just https
has [ 'rooturl', 'rooturlredirect', 'rooturlredirects', 'rooturlredirectvpn', 'rooturlredirectvpns', 'rootnfs', 'top_folders' ];

# length of eventual path in rooturl after hostname
has rooturidirlenght => 0;

my $uaroot = Mojo::UserAgent->new->max_redirects(10)->request_timeout(1);

sub register {
    my ($self, $app) = @_;
    my $rooturl = $app->mc->rootlocation;
    $self->rooturl($rooturl);
    {
        my $i = index($rooturl, '://');
        if ($i > 0) {
            my $j = index($rooturl, '/', $i+4);
            $self->rooturidirlenght(length($rooturl)-$j) if $j > 0;
        }
    }

    my $mcconfig = $app->mcconfig;

    $self->rootnfs($mcconfig->root_nfs);
    $self->top_folders($mcconfig->top_folders);

    my $redirect = $rooturl;
    if ($redirect = $mcconfig->redirect) {
        $redirect  = "http://$redirect" unless 'http://' eq substr($redirect, 0, length('http://'));
    } else {
        $redirect = $rooturl;
    }
    $self->rooturlredirect($redirect);
    my $redirects = $redirect =~ s/http:/https:/r;
    $self->rooturlredirects($redirects);

    if (my $redirectvpn = $mcconfig->redirect_vpn) {
        $redirectvpn = "http://$redirectvpn" unless 'http://' eq substr($redirectvpn, 0, length('http://'));
        $self->rooturlredirectvpn($redirectvpn);
        my $redirectvpns = $redirectvpn =~ s/http:/https:/r;
        $self->rooturlredirectvpns($redirectvpns);
    }
    $app->helper( 'mc.root' => sub { $self; });
}

sub is_remote {
    return 1;
}

sub realpath {
    my ($self, $path, $deep) = @_;
    return undef unless $path;
    my $nfs = $self->rootnfs;

    if ($nfs) {
        my $localpath = $nfs . $path;
        my $realpathlocal = Cwd::realpath($localpath);

        if ($realpathlocal && (0 == rindex($realpathlocal, $nfs, 0))) {
            my $realpath = substr($realpathlocal, length($nfs));
            return $realpath if $realpath ne $path;
        }
    } elsif ($deep) {
        my $path1 = $path . '/';
        my $rootlocation = $self->rooturl;
        my $url = $rootlocation . $path1 . '?realpath';
        my $ua = Mojo::UserAgent->new->max_redirects(0)->request_timeout(1);
        my $tx = $ua->head($url, {'User-Agent' => 'MirrorCache/detect_redirect'});
        my $res = $tx->res;

        # redirect on oneself
        if ($res->is_redirect && $res->headers) {
            my $location1 = $res->headers->location;
            $location1 =~ s/\?realpath=?$//;
            return substr($location1,$self->rooturidirlenght(),-1) if '/' eq substr($location1,0,1);
            if ($location1 && $path1 ne substr($location1, -length($path1))) {
                my $i = rindex($location1, $rootlocation, 0);
                if ($i ne -1) {
                    # remove trailing slash we added earlier
                    my $location = substr($location1, 0, -1);
                    if ($rootlocation eq substr($location, 0, length($rootlocation))) {
                        return substr($location, length($rootlocation));
                    }
                }
            }
        }
    }
    return undef;
}

sub is_reachable {
    my $res = 0;
    eval {
        my $tx = $uaroot->head(shift->rooturlredirect);
        $res = 1 if $tx->result->code < 399 || $tx->result->code == 403;
    };
    return $res;
}

sub is_file {
    my $self = shift;
    my $rooturlpath = $self->rooturl . shift;
    my $res;
    eval {
        my $ua = Mojo::UserAgent->new->max_redirects(0);
        my $tx = $ua->head($rooturlpath);
        $res = $tx->result;
    };
    return ($res && !$res->is_error && !$res->is_redirect);
}

sub is_dir {
    my $res = is_file($_[0], $_[1] . '/');
    return $res;
}

sub render_file {
    my ($self, $dm, $filepath, $not_miss, $from_nfs) = @_;
    my $c = $dm->c;
    my $nfs = $self->rootnfs;
    if ($nfs && ($dm->must_render_from_root || $from_nfs) && -f ($nfs . $filepath)) {
        $c->render_file(filepath => $nfs . $filepath, content_type => $dm->mime, content_disposition => 'inline');
        $c->stat->redirect_to_root($dm, $not_miss);
        return 1;
    }

    $c->redirect_to($self->location($dm, $filepath));
    $c->stat->redirect_to_root($dm, $not_miss);
    return 1;
}

sub render_file_if_nfs {
    my ($self, $dm, $filepath) = @_;
    my $nfs = $self->rootnfs;
    return undef unless $nfs;

    my $c = $dm->c;

    return undef unless($dm->must_render_from_root && -f $nfs . $filepath);
    $c->render_file(filepath => $nfs . $filepath, content_type => $dm->mime, content_disposition => 'inline');
    $c->stat->redirect_to_root($dm, 1);
    return 1;
}

sub location {
    my ($self, $dm, $filepath) = @_;
    $filepath = "" unless $filepath;
    my $c;
    $c = $dm->c if $dm;
    if ($dm && $self->rooturlredirectvpn && $dm->vpn) {
        return $self->rooturlredirectvpn . $filepath unless $c && $c->req->is_secure;
        return $self->rooturlredirectvpns . $filepath;
    }
    return $self->rooturlredirect . $filepath unless $c && $c->req->is_secure;
    return $self->rooturlredirects . $filepath;
}

sub looks_like_file {
    my $f = shift;
    return 0 if $f eq '../';
    return 0 if rindex($f, '/', length($f)-2) > -1;
    return 1;
};

sub _detect_ln_in_the_same_folder {
    my ($self, $dir, $file) = @_;
    my $nfs = $self->rootnfs;
    unless ($nfs) {
        my $dir1 = $dir . '/';
        my $rootlocation = $self->rooturl;
        my $url = $rootlocation . $dir1 . $file;
        my $ua = Mojo::UserAgent->new->max_redirects(0)->request_timeout(2);
        my $tx = $ua->head($url, {'User-Agent' => 'MirrorCache/detect_redirect'});
        my $res = $tx->res;
        my $etag = $res->headers->etag;

        # redirect on oneself
        if ($res->is_redirect && $res->headers) {
            my $location = $res->headers->location;
            my $url1 = $rootlocation . $dir1;
            if ($location && $url1 eq substr($location, 0, length($url1))) {
                my $ln = substr($location, length($url1));
                my $version;
                $version = $self->detect_version($ln) if $ln;
                return ($ln, $etag) if -1 == index($ln, '/');
            }
        }
        return undef;
    }

    my $dest;
    my $thisfile = $nfs . $dir . '/' . $file;
    eval {
        $dest = readlink($thisfile);
    };
    return undef unless $dest;
    my $res;
    my $realfile;
    my $version;
    eval {
        my $x = Mojo::File->new($dest);

        return undef unless $x->dirname eq '.' || $x->dirname eq $dir;
        $res = $x->basename;
        $version = $self->detect_version($res) if $res;

        $realfile = $dest;
        $realfile = $nfs . $dir . '/' . $dest if $x->dirname eq '.';
    };
    return ($res, $self->etag($realfile), $version);
}

# this is simillar to self->realpath, just detects symlinks in current folder
sub detect_ln_in_the_same_folder {
    my ($self, $path) = @_;
    my $f = Mojo::File->new($path);
    my ($res, $etag, $version) = $self->_detect_ln_in_the_same_folder($f->dirname, $f->basename);
    return undef unless $res;
    return ($f->dirname . '/' . $res, $etag, $version);
}

# this is complicated to avoid storing big html in memory
# we parse and execute callback $sub on the fly
sub foreach_filename {
    my $self = shift;
    my $dir  = shift;
    my $sub  = shift;
    my $P    = shift;
    if ($dir eq '/' && $self->top_folders) {
        for (split ' ', $self->top_folders) {
            $sub->($_ . '/');
        }
        return 1;
    }
    my $ua   = Mojo::UserAgent->new;
    my $tx   = $ua->get($self->rooturl . $dir . '/?F=1&json');
    return 0 unless $tx->result->code == 200;

    return $self->_foreach_filename_json($dir, $sub, $P, $ua, $tx) if -1 < index($tx->result->headers->content_type, 'json');

    return $self->_foreach_filename_html($dir, $sub, $P, $ua, $tx);
}

# we cannot use mojo dom here because it takes too much RAM for huge html
# my $dom = $tx->result->dom;
sub _foreach_filename_html {
    my $self = shift;
    my $dir  = shift;
    my $sub  = shift;
    my $P    = shift;
    my $ua   = shift;
    my $tx   = shift;

    my $href = '';
    my $href20 = '';
    my $tag = '';
    my %desc;
    my $start = sub {
        my ($tag, $v) = @_;
        return undef unless $tag eq 'a' && $v;
        my $h = $v->{href};
        $h =~ s{^\./}{};
        $h = uri_unescape($h);
        return undef unless looks_like_file($h);
        $href = $h;
    };
    my $end = sub {
        $href = '';
        $href20 = '';
        $tag = '';
    };
    my $text = sub {
        my $t = shift;
        $t = trim $t if $t;

        $href20 = substr($href,0,20) if $href && !$href20;

        if ($t && ($href20 eq substr($t,0,20))) {
            if ($desc{name} && (!$P || $desc{name} =~ $P)) {
                my $target;

                if ($desc{name} =~ m/(GNOME_.*|.*(Media|[C|c]urrent|Next))\.iso(\.sha256(\.asc)?)?/) {
                    ($target, undef, undef) = $self->_detect_ln_in_the_same_folder($dir, $desc{name});
                }
                $sub->($desc{name}, $desc{size}, undef, $desc{mtime}, $target);
                %desc = ();
            }
            $desc{name} = $href;
        } elsif ($desc{name} && (!$P || $desc{name} =~ $P)) {
            my @fields = split /(\d{2}-[A-Z][a-z]{2}-\d{4} \d{2}\:\d{2})\s+(-|\d+)/, $t;
            if (3 == @fields) {
                eval {
                    my $dt = localtime->strptime($fields[1],'%d-%b-%Y %H:%M');
                    $desc{mtime} = $dt->epoch;
                    my $size = $fields[2];
                    $size = undef if $size eq '-';
                    $desc{size} = $size;
                    1;
                }; #  or print STDERR "Error parsing file date:" . $@;
            }
        }
    };

    my $p = HTML::Parser->new(
        api_version => 3,
        start_h => [$start, "tagname, attr"],
        text_h  => [$text,  "dtext" ],
        end_h   => [$end,   "tagname"],
    );
    $p->utf8_mode(1);

    my $offset = 0;
    while (1) {
        my $chunk = $tx->result->get_body_chunk($offset);
        if (!defined($chunk)) {
            $ua->loop->one_tick unless $ua->loop->is_running;
            next;
        }
        my $l = length $chunk;
        last unless $l > 0;
        $offset += $l;
        $p->parse($chunk);
    }
    if ($desc{name} && (!$P || $desc{name} =~ $P)) {
        my $target;

        if ($desc{name} =~ m/(GNOME_.*|.*(Media|[C|c]urrent|Next))\.iso(\.sha256(\.asc)?)?/) {
            ($target, undef, undef) = $self->_detect_ln_in_the_same_folder($dir, $desc{name});
        }
        $sub->($desc{name}, $desc{size}, undef, $desc{mtime}, $target);
        %desc = ();
    }
    $p->eof;
    return 1;
}

sub _foreach_filename_json {
    my $self = shift;
    my $dir  = shift;
    my $sub  = shift;
    my $P    = shift;
    my $ua   = shift;
    my $tx   = shift;

    my $cnt = 0;

    my $value = decode_json $tx->result->body;
    die "JSON top level is not array" unless ref($value) eq 'ARRAY';

    for my $hashref (@{$value}) {
        my $n = $hashref->{name} // $hashref->{n};
        $n = $n . '/' if $hashref->{type} // '' eq 'directory' && '/' ne substr $n, -1;
        next unless $n;
        $sub->(
            $n,
            $hashref->{size}  // $hashref->{s},
            undef,
            $hashref->{mtime} // $hashref->{m},
        ) if $sub;
        $cnt++;
    }
    return $cnt;
}

sub etag {
    my ($self, $file) = @_;
    my $etag;
    eval {
        my @stat = stat($file);
        my $size  = $stat[7];
        my $mtime = $stat[9];
        $etag = sprintf('%X', $mtime // 0) . '-' . sprintf('%X', $size // 0);
    };
    return $etag;
}

sub detect_version {
    my ($self, $file) = @_;
    return Directory::Scanner::OBSMediaVersion::parse_version($file);
}

1;
