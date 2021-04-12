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

package MirrorCache::WebAPI::Plugin::RootRsync;
use Mojo::Base 'Mojolicious::Plugin';

use File::Listing::Rsync;
use Mojo::File;
use Encode ();
use URI::Escape ('uri_unescape');
use File::Basename;
use POSIX qw( strftime );
use Data::Dumper;

use MirrorCache::Utils;

# rooturlredirect as defined in MIRRORCACHE_REDIRECT
# rooturlsredirect same as above just https
has [ 'app', 'reader', 'rooturlredirect', 'rooturlsredirect' ];

sub register {
    my ($self, $app, $args) = @_;
    my $url = $args->{url};
    die "Rsync url was not provided" unless $url;
    $self->app( $app );
    $self->reader( new File::Listing::Rsync->new->init($url) );
    my $redirect;
    if ($redirect = $ENV{MIRRORCACHE_REDIRECT}) {
        $redirect = "http://$redirect" unless 'http://' eq substr($redirect, 0, length('http://'));
    } else {
    	$redirect = substr($url,0,length('rsync://'), 'http://');
    }
    $self->rooturlredirect($redirect);
    $redirect = substr($redirect,0,length('http://'),'https://');
    $self->rooturlsredirect($redirect);
    $app->helper( 'mc.root' => sub { $self; });
}

sub is_remote {
    return 1;
}

sub is_reachable {
    my $res = 0;
    eval {
        shift->reader->readdir('', sub {
            $res = 1;
            return 2;
        });
    };
    return $res;
}

sub is_file {
    my ($self, $path) = @_;
    my $res = 0;
    my $f = Mojo::File->new($path);
    eval {
        my $basename = $f->basename;
        $self->reader->readdir($f->dirname, sub {
            if ($_[0] eq $basename) {
                $res = 1;
                return 2;
            }
        });
    };
    return $res;
}

sub is_dir {
    my ($self, $path) = @_;
    my $res = 0;
    eval {
        $self->reader->readdir($path, sub {
            $res = 1;
            return 2;
        });
    };

    return $res;
}

sub render_file {
    my ($self, $c, $filepath, $not_miss) = @_;
    $c->redirect_to($self->location($c, $filepath));
    $c->stat->redirect_to_root(0) unless $not_miss;
    return 1;
}

sub location {
    my ($self, $c, $filepath) = @_;
    $filepath = "" unless $filepath;
    return $self->rooturlredirect . $filepath unless $c && $c->req->is_secure;
    return $self->rooturlsredirect . $filepath;
}

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
    $self->reader->readdir($dir, sub {
        my ($name, $size, $mmode, $mtime) = @_;
        return undef unless $name && $name ne '.';
        $sub->($name, $size, $mmode, $mtime);
    });

    return 1;
}

1;
