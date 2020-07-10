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
my $types = Mojolicious::Types->new;
my $app;

sub register {
    (my $self, $app) = @_;
    $url = $app->mc->rootlocation;
    $app->helper( 'mc.root' => sub { $self->singleton; });
}

sub is_file {
    my $urlpath = $url . $_[1];
    my $ua = Mojo::UserAgent->new;
    my $tx = $ua->head($urlpath);
    my $res = $tx->result->code; 
    # my $res = Mojo::UserAgent->new->head($url . $_[1])->result->code;
    return $res == 200 || $res == 302;
}

sub is_dir {
    my $urlpath = $url . $_[1] . '/';
    my $res = 404;
    eval {
        my $ua = Mojo::UserAgent->new;
        my $tx = $ua->head($urlpath);
        $res = $tx->result->code;
        # $res = Mojo::UserAgent->new->head($urlpath)->result->code;
        
    } or $app->emit_event('mc_debug', {url => "u$urlpath", err => $@});

    return $res == 200 || $res == 302;
}

sub render_file {
    my ($self, $c, $filepath) = @_;
    return $c->redirect_to($url . $filepath);
}

sub list_filenames {
    my $self    = shift;
    my $dir     = shift;
    my $tx = Mojo::UserAgent->new->get($url . $dir);
    my @res = ();
    return \@res unless $tx->result->code == 200;
    my $dom = $tx->result->dom;
    for my $i (sort { $a->attr->{href} cmp $b->attr->{href} } $dom->find('a')->each) {
        my $href = $i->attr->{href};
        my $text = trim $i->text;
        if ($text eq $href) { # && -f $localdir . $text) {
            $text =~ s/\/$//;
            push @res, $text;
        }
    }
    return \@res;
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
