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
use Mojolicious::Types;
use Mojo::Util ('trim');
use Encode ();

use Data::Dumper;

sub singleton { state $root = shift->SUPER::new; return $root; };

my $url;
my $urllen;
my $types = Mojolicious::Types->new;
my $app;

sub register {
    (my $self, $app) = @_;
    $url = $app->mc->rootlocation;
    $urllen = length $url;
    $app->helper( 'mc.root' => sub { $self->singleton; });
}

sub is_remote {
    return 1;
}

sub is_file {
    my $urlpath = $url . $_[1];
    my $ua = Mojo::UserAgent->new;
    my $tx = $ua->head($urlpath);
    my $res = $tx->result; 
    return ($res && !$res->is_error);
}

sub is_dir {
    my $urlpath = $url . $_[1] . '/';
    my $res;
    eval {
        my $ua = Mojo::UserAgent->new;
        my $tx = $ua->head($urlpath);
        $res = $tx->result;
    } or $app->emit_event('mc_debug', {url => "u$urlpath", err => $@});
    $app->emit_event('mc_debug', {url => "u$urlpath", code => ($res && !$res->is_error)});

    return ($res && !$res->is_error);
}

sub is_self_redirect {
    my ($self, $path) = @_;
    $path = $path . '/';
    my $urlpath = $url . $path;
    $app->emit_event('mc_debug', {url => "r$urlpath"});
    my $res;
    eval {
        my $ua = Mojo::UserAgent->new;
        my $tx = $ua->head($urlpath);
        
        $res = $tx->result;
    } or $app->emit_event('mc_debug', {url => "r$urlpath", err => $@});
    $app->emit_event('mc_debug', {url => "r$urlpath", code => $res->code});

    return "" unless $res && !$res->is_error && $res->is_redirect && $res->headers;
    my $location = $res->headers->location;
    return "" unless $location && $path ne substr($location, -length($path));

    my $i = rindex($location, $url, 0);
    $app->emit_event('mc_debug', {url => "$urlpath", location => $location, i => $i});
    if ($i ne -1) {
        $app->emit_event('mc_debug', {url => "$urlpath", location => substr($location, $urllen)});
        return substr $location, $urllen; 
    }
    return "";
}

sub render_file {
    my ($self, $c, $filepath) = @_;
    return $c->redirect_to($url . $filepath);
}

sub list_filenames {
    my $self    = shift;
    my $dir     = shift;
    my $tx = Mojo::UserAgent->new->get($url . $dir . '/');
    my @res = ();
    return \@res unless $tx->result->code == 200;
    my $dom = $tx->result->dom;
    for my $i (sort { $a->attr->{href} cmp $b->attr->{href} } $dom->find('a')->each) {
        my $href = $i->attr->{href};
        my $text = trim $i->text;
        if ($text eq $href) { # && -f $localdir . $text) {
            # $text =~ s/\/$//;
            push @res, $text;
        }
    }
    return \@res;
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
    my $children = $self->list_filenames($dir);

    my $cur_path = Encode::decode_utf8( Mojo::Util::url_unescape( $urlpath) );
    for my $basename ( sort { $a cmp $b } @$children ) {
        my $file = "$dir/$basename";
        my $furl  = Mojo::Path->new($url . $cur_path)->trailing_slash(0);
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
        };
    }
    return \@files;
}

sub _get_ext {
    $_[0] =~ /\.([0-9a-zA-Z]+)$/ || return;
    return lc $1;
}

1;
