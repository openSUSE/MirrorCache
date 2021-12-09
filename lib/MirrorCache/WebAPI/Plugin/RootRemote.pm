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
use URI::Escape ('uri_unescape');
use File::Basename;
use HTML::Parser;
use Time::Piece;

# rooturlredirect as defined in MIRRORCACHE_REDIRECT
# rooturlsredirect same as above just https
has [ 'rooturl', 'rooturlredirect', 'rooturlredirects', 'rooturlredirectvpn', 'rooturlredirectvpns' ];

my $uaroot = Mojo::UserAgent->new->max_redirects(10)->request_timeout(1);

sub register {
    my ($self, $app) = @_;
    my $rooturl = $app->mc->rootlocation;
    $self->rooturl($rooturl);

    my $redirect = $rooturl;
    if ($redirect = $ENV{MIRRORCACHE_REDIRECT}) {
        $redirect  = "http://$redirect" unless 'http://' eq substr($redirect, 0, length('http://'));
    } else {
        $redirect = $rooturl;
    }
    $self->rooturlredirect($redirect);
    my $redirects = $redirect =~ s/http:/https:/r;
    $self->rooturlredirects($redirects);

    if (my $redirectvpn = $ENV{MIRRORCACHE_REDIRECT_VPN}) {
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
    my ($self, $dm, $filepath, $not_miss) = @_;
    my $c = $dm->c;
    $c->redirect_to($self->location($dm, $filepath));
    $c->stat->redirect_to_root($dm, $not_miss);
    return 1;
}

sub location {
    my ($self, $dm, $filepath) = @_;
    $filepath = "" unless $filepath;
    my $c;
    $c = $dm->c if $dm;
    if ($dm && $ENV{MIRRORCACHE_REDIRECT_VPN} && $dm->vpn) {
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

sub _detect_ln {
    return undef unless $ENV{MIRRORCACHE_ROOT_NFS};
    my ($dir, $file) = @_;
    return undef unless $file && $file =~ m/.*(Media|Current)\.iso(\.sha256)?/;

    my $dest;
    eval {
        $dest = readlink($ENV{MIRRORCACHE_ROOT_NFS} . $dir . '/' . $file);
    };
    return undef unless $dest;
    my $res;
    eval {
        $dest = Mojo::File->new($dest);

        return undef unless $dest->dirname eq '.' || $dest->dirname eq $dir;
        $res = $dest->basename;
    };
    return $res;
}

sub detect_ln {
    return undef unless $ENV{MIRRORCACHE_ROOT_NFS};
    my ($self, $path) = @_;
    my $f = Mojo::File->new($path);
    my $res = _detect_ln($f->dirname, $f->basename);
    return undef unless $res;
    return $f->dirname . '/' . $res;
}

# this is complicated to avoid storing big html in memory
# we parse and execute callback $sub on the fly
sub foreach_filename {
    my $self = shift;
    my $dir  = shift;
    my $sub  = shift;
    if ($dir eq '/' && $ENV{MIRRORCACHE_TOP_FOLDERS}) {
        for (split ' ', $ENV{MIRRORCACHE_TOP_FOLDERS}) {
            $sub->($_ . '/');
        }
        return 1;
    }
    my $ua   = Mojo::UserAgent->new;
    my $tx   = $ua->get($self->rooturl . $dir . '/?F=1');
    return 0 unless $tx->result->code == 200;
    # we cannot use mojo dom here because it takes too much RAM for huge html
    # my $dom = $tx->result->dom;

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
            if ($desc{name}) {
                my $target = _detect_ln($dir, $desc{name});
                $sub->($desc{name}, $desc{size}, undef, $desc{mtime}, $target);
                %desc = ();
            }
            $desc{name} = $href;
        } elsif ($desc{name}) {
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
    if ($desc{name}) {
        my $target = detect_ln($dir, $desc{name});
        $sub->($desc{name}, $desc{size}, undef, $desc{mtime}, $target);
        %desc = ();
    }
    $p->eof;
    return 1;
}

1;
