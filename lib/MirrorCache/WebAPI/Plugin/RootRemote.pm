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

package MirrorCache::WebAPI::Plugin::RootRemote;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::Util ('trim');
use Encode ();
use URI::Escape ('uri_unescape');
use File::Basename;
use HTML::Parser;
use Data::Dumper;

sub singleton { state $root = shift->SUPER::new; return $root; };

my $rooturl;
my $rooturls; # same as $rooturl just s/http:/https:
my $rooturlsfallback; # as defined in MIRRORCACHE_FALLBACK_HTTPS_REDIRECT

my $app;
my $uaroot = Mojo::UserAgent->new->max_redirects(10)->request_timeout(1);

sub register {
    (my $self, $app) = @_;
    $rooturl = $app->mc->rootlocation;
    $rooturls = $rooturl =~ s/http:/https:/r;
    if (my $fallback = $ENV{MIRRORCACHE_FALLBACK_HTTPS_REDIRECT}) {
        $rooturlsfallback = $fallback;
    } else {
        $rooturlsfallback = $rooturls;
    }
    $app->helper( 'mc.root' => sub { $self->singleton; });
}

sub is_remote {
    return 1;
}

sub is_reachable {
    my $res = 0;
    eval {
        my $tx = $uaroot->get($rooturl);
        $res = 1 if $tx->result->code < 399;
    };
    return $res;
}

sub is_file {
    my $rooturlpath = $rooturl . $_[1];
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
    my ($self, $c, $filepath, $not_miss) = @_;
    $c->redirect_to($self->location($c, $filepath));
    $c->stat->redirect_to_root($not_miss? 1 : 0);
    return 1;
}

sub location {
    my ($self, $c, $filepath) = @_;
    $filepath = "" unless $filepath;
    return $rooturl . $filepath unless $c && $c->req->is_secure;
    return $rooturls . $filepath if (!$filepath || substr($filepath,length($filepath)-1,1) eq "/"); # dont use fallback for folder checks
    return $rooturlsfallback . $filepath;
}

sub looks_like_file {
    my $f = shift;
    return 0 if rindex($f, '/', length($f)-2) > -1;
    return 1;
};

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
    my $tx   = $ua->get($rooturl . $dir . '/?F=1');
    return 0 unless $tx->result->code == 200;
    # we cannot use mojo dom here because it takes too much RAM for huge html
    # my $dom = $tx->result->dom;

    my $href = '';
    my $start = sub {
        return undef unless $_[0] eq 'a' && $_[1];
        $href = $_[1]->{href};
        $href =~ s{^\./}{};
        $href = uri_unescape($href);
    };
    my $end = sub {
        $href = '';
    };
    my $text = sub {
        my $t = trim shift;
        $sub->($t) if $t && ($href eq $t) && looks_like_file($t);
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
    $p->eof;
    return 1;
}


# unused: $tx->result->dom takes ~70 Mb ram for 7k files TODO
sub list_filenames {
    my $self = shift;
    my $dir  = shift;
    my $tx   = Mojo::UserAgent->new->get($rooturl . $dir . '/');
    my @res  = ();
    return \@res unless $tx->result->code == 200;
    my $dom = $tx->result->dom;
    # TODO move root html tag to config
    my @items = $dom->find('main')->each;
    @items = $dom->find('ul')->each unless @items;
    for my $ul (@items) {
        for my $i ($ul->find('a')->each) {
            my $text = trim $i->text;
            my $href = $i->attr->{href};
            next unless $href;
            if ('/' eq substr($href, -1)) {
                $href = basename($href) . '/';
            } else {
                $href = basename($href);
            }
            $href = uri_unescape($href);
            if ($text eq $href) { # && -f $localdir . $text) {
                # $text =~ s/\/$//;
                push @res, $text;
            }
        }
    }
    my %hash   = map { $_, 1 } @res;
    @res = sort keys %hash;
    return \@res;
}

1;
