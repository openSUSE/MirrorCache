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

package MirrorCache::WebAPI::Plugin::RootLocal;
use Mojo::Base 'Mojolicious::Plugin';

use Encode ();
use DirHandle;
use Mojolicious::Types;

sub singleton { state $root = shift->SUPER::new; return $root; };

my $rootpath;
my $app;
my $types = Mojolicious::Types->new;

sub register {
    (my $self, $app) = @_;
    $rootpath = $app->mc->rootlocation;
    push @{$app->static->paths}, $rootpath;
    $app->helper( 'mc.root' => sub { $self->singleton; });
}

sub is_remote {
    return 0;
}

sub is_file {
    return 1 unless $_[1];
    return -f $rootpath . $_[1];
}

sub is_dir {
    return 1 unless $_[1];
    return -d $rootpath . $_[1];
}

sub render_file {
    my ($self, $c, $filepath) = @_;
    return !!$c->reply->static($filepath);
}

sub list_filenames {
    my $self    = shift;
    my $dir     = shift;
    return Mojo::File->new($rootpath . $dir)->list({dir => 1})->map( 'basename' )->to_array;
}

sub _list_files {
    my $dir = shift || return [];
    my $dh = DirHandle->new($dir);
    return [] unless $dh;
    my @children;
    while ( defined( my $ent = $dh->read ) ) {
        next if $ent eq '.' or $ent eq '..';
        push @children, Encode::decode_utf8($ent);
    }
    return [ @children ];
}

sub list_files_from_db {
    my $self    = shift;
    my $urlpath = shift;
    my $folder_id = shift;
    my $dir = shift;
    my @files   =
        ( $urlpath eq '/' )
        ? ()
        : ( { url => '../', name => 'Parent Directory', size => '', type => '', mtime => '' } );
    my @childrenfiles = $app->schema->resultset('File')->search({folder_id => $folder_id});

    my $cur_path = Encode::decode_utf8( Mojo::Util::url_unescape( $urlpath ) );
    for my $child ( @childrenfiles ) {
        my $basename = $child->name;
        my $file = "$rootpath$dir/$basename";
        my $url  = Mojo::Path->new($cur_path)->trailing_slash(0);
        my $is_dir = '/' eq substr($basename, -1)? 1 : 0;
        $basename = substr($basename, 0, -1) if $is_dir;
        push @{ $url->parts }, $basename;
        if ($is_dir) {
            $basename .= '/';
            $url->trailing_slash(1);
        }
        my $mime_type = $types->type( _get_ext($file) || 'txt' ) || 'text/plain';

        push @files, {
            url   => $url,
            name  => $basename,
            size  => 0,
            type  => $mime_type,
            mtime => '',
        };
    }
    return \@files;
}

sub list_files {
    my $self    = shift;
    my $urlpath = shift;
    my $dir     = shift;
    my @files   =
        ( $urlpath eq '/' )
        ? ()
        : ( { url => '../', name => 'Parent Directory', size => '', type => '', mtime => '' } );
    my $children = _list_files($rootpath . $dir);

    my $cur_path = Encode::decode_utf8( Mojo::Util::url_unescape( $urlpath ) );
    for my $basename ( sort { $a cmp $b } @$children ) {
        my $file = "$rootpath$dir/$basename";
        my $url  = Mojo::Path->new($cur_path)->trailing_slash(0);
        push @{ $url->parts }, $basename;

        my $is_dir = -d $file;
        my @stat   = stat _;
        if ($is_dir) {
            $basename .= '/';
            $url->trailing_slash(1);
        }

        my $mime_type =
            $is_dir
            ? 'directory'
            : ( $types->type( _get_ext($file) || 'txt' ) || 'text/plain' );
        my $mtime = Mojo::Date->new( $stat[9] )->to_string();

        push @files, {
            url   => $url,
            name  => $basename,
            size  => $stat[7] || 0,
            type  => $mime_type,
            mtime => $mtime,
        };
    }
    return \@files;
}

sub _get_ext {
    $_[0] =~ /\.([0-9a-zA-Z]+)$/ || return;
    return lc $1;
}

1;
