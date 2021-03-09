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
use Mojolicious::Types;
use Mojo::File;
use Encode ();
use URI::Escape ('uri_unescape');
use File::Basename;
use Data::Dumper;

# rooturlredirect as defined in MIRRORCACHE_REDIRECT
# rooturlsredirect same as above just https
has [ 'app', 'reader', 'rooturlredirect', 'rooturlsredirect' ];

my $types = Mojolicious::Types->new;

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
    my $res = is_file($_[0], $_[1] . '/.');
    return $res;
}

sub render_file {
    my ($self, $c, $filepath, $not_miss) = @_;
    $c->redirect_to($self->location($c, $filepath));
    $c->stat->redirect_to_root unless $not_miss;
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
        my $name = shift;
        $sub->($name) unless $name eq '.';
    });

    return 1;
}

sub _by_filename {
    $b->{dir} cmp $a->{dir} ||
    $a->{name} cmp $b->{name};
}

sub list_files_from_db {
    my $self    = shift;
    my $urlpath = shift;
    my $folder_id = shift;
    my $dir = shift;
    my @res   =
        ( $urlpath eq '/' || $urlpath eq '/download' )
        ? ()
        : ( { url => '../', name => 'Parent Directory', size => '', type => '', mtime => '' } );
    my @files;
    my @childrenfiles = $self->app->schema->resultset('File')->search({folder_id => $folder_id});

    my $cur_path = Encode::decode_utf8( Mojo::Util::url_unescape( $urlpath ) );
    for my $child ( @childrenfiles ) {
        my $basename = $child->name;
        my $url  = Mojo::Path->new($cur_path)->trailing_slash(0);
        my $is_dir = '/' eq substr($basename, -1)? 1 : 0;
        $basename = substr($basename, 0, -1) if $is_dir;
        push @{ $url->parts }, $basename;
        if ($is_dir) {
            $basename .= '/';
            $url->trailing_slash(1);
        }
        my $mime_type = $types->type( _get_ext($basename) || 'txt' ) || 'text/plain';

        push @files, {
            url   => $url,
            name  => $basename,
            size  => 0,
            type  => $mime_type,
            mtime => '',
            dir   => $is_dir,
        };
    }
    push @res, sort _by_filename @files;
    return \@res;
}

sub list_files {
    my $self    = shift;
    my $urlpath = shift;
    my $dir     = shift;
    my @res   =
        ( $urlpath eq '/' )
        ? ()
        : ( { url => '../', name => 'Parent Directory', size => '', type => '', mtime => '' } );
    my @files;
    my $children = $self->list_filenames($dir);

    my $cur_path = Encode::decode_utf8( Mojo::Util::url_unescape( $urlpath) );
    for my $basename ( sort { $a cmp $b } @$children ) {
        my $file = "$dir/$basename";
        my $furl  = Mojo::Path->new($cur_path)->trailing_slash(0);
        my $is_dir = (substr $file, -1) eq '/' || $self->is_dir($file);
        if ($is_dir) {
            # directory points to this server
            $furl = Mojo::Path->new($cur_path)->trailing_slash(0);
            push @{ $furl->parts }, $basename;
            $furl = $furl->trailing_slash(1);
        } else {
            push @{ $furl->parts }, $basename;
        }

        my $mime_type =
            $is_dir
            ? 'directory'
            : ( $types->type( _get_ext($file) || 'txt' ) || 'text/plain' );
        my $mtime = 'mtime';

        push @files, {
            url   => $furl,
            name  => $basename,
            size  => '?',
            type  => $mime_type,
            mtime => $mtime,
            dir   => $is_dir,
        };
    }
    push @res, sort _by_filename @files;
    return \@res;
}

sub _get_ext {
    $_[0] =~ /\.([0-9a-zA-Z]+)$/ || return;
    return lc $1;
}

1;
