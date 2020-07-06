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
# with this program; if not, see <http://www.gnu.org/licenses/>.

# inspired by and has some parts from Mojolicious-Plugin-Directory
package MirrorCache::WebAPI::Plugin::Dir;
use Mojo::Base 'Mojolicious::Plugin';

use Cwd ();
use Encode ();
use DirHandle;
use Mojolicious::Types;
use Mojo::JSON qw(encode_json);

use Data::Dumper;

# Stolen from Plack::App::Direcotry
my $dir_page = <<'PAGE';
<html><head>
  <title>Index of <%= $cur_path %></title>
  <meta http-equiv="content-type" content="text/html; charset=utf-8" />
  <style type='text/css'>
table { width:100%%; }
.name { text-align:left; }
.size, .mtime { text-align:right; }
.type { width:11em; }
.mtime { width:15em; }
  </style>
</head><body>
<h1>Index of <%= $cur_path %></h1>
<hr />
<table>
  <tr>
    <th class='name'>Name</th>
    <th class='size'>Size</th>
    <th class='type'>Type</th>
    <th class='mtime'>Last Modified</th>
  </tr>
  % for my $file (@$files) {
  <tr><td class='name'><a href='<%= $file->{url} %>'><%== $file->{name} %></a></td><td class='size'><%= $file->{size} %></td><td class='type'><%= $file->{type} %></td><td class='mtime'><%= $file->{mtime} %></td></tr>
  % }
</table>
<hr />
</body></html>
PAGE

my $types = Mojolicious::Types->new;

sub register {
    my $self = shift;
    my ( $app, $args ) = @_;
    my $root  = $args->{root};
    my $route = $args->{route};

    my $route_len = length($route);
    
    $app->hook(
        before_dispatch => sub {
            return indx(shift, $root, $route, $route_len);
        }
    );
    return $app;
}

sub indx {
    my ($c, $root, $route, $route_len) = @_;
    print("XX $root :: $route :: $route_len :: " . $c->req->url->path . "::" . rindex($c->req->url->path, $route, 0) . "\n");
    return undef unless 0 eq rindex($c->req->url->path, $route, 0);

    my $file = Mojo::Util::url_unescape(substr($c->req->url->path, $route_len));
    print("YY $root :: $file \n");
    if ( -f $root . $file ) {
        return $c->mirrorcache->render_file($file, $root, $route);
    }
    return undef unless -d $root . $file;
    return render_dir($c, $file, $root, $route);
}

sub render_dir {
    my $c     = shift;
    my $dir   = shift;
    my $root  = shift;
    my $route = shift;
    my $json  = shift;

    if ( $c->req->url->path ne "/" && ! $c->req->url->path->trailing_slash ) {
        $c->redirect_to($c->req->url->path->trailing_slash(1));
        return undef;
    }

    my @files =
        ( $c->req->url->path eq '/' )
        ? ()
        : ( { url => '../', name => 'Parent Directory', size => '', type => '', mtime => '' } );
    my $children = list_files($root . $dir);

    my $cur_path = Encode::decode_utf8( Mojo::Util::url_unescape( $c->req->url->path ) );
    for my $basename ( sort { $a cmp $b } @$children ) {
        my $file = "$root$dir/$basename";
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
            : ( $types->type( get_ext($file) || 'txt' ) || 'text/plain' );
        my $mtime = Mojo::Date->new( $stat[9] )->to_string();

        push @files, {
            url   => $url,
            name  => $basename,
            size  => $stat[7] || 0,
            type  => $mime_type,
            mtime => $mtime,
        };
    }

    my $any = { inline => $dir_page, files => \@files, cur_path => $cur_path };
    if ($json) {
        $c->respond_to(
            json => { json => encode_json(\@files) },
            any  => $any,
        );
    }
    else {
        $c->render( %$any );
    } 
}

sub get_ext {
    $_[0] =~ /\.([0-9a-zA-Z]+)$/ || return;
    return lc $1;
}

sub list_files {
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

1;
