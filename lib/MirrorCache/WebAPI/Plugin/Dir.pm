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

use Mojo::JSON qw(encode_json);

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

my $root;

sub register {
    my $self = shift;
    my $app = shift;

    $root = $app->mc->root;
    my $route = $app->mc->route;
    my $route_len = length($route);

    $app->hook(
        before_dispatch => sub {
            return indx(shift, $route, $route_len);
        }
    );
    return $app;
}

sub indx {
    my ($c, $route, $route_len) = @_;
    return undef unless 0 eq rindex($c->req->url->path, $route, 0);

    my $file = Mojo::Util::url_unescape(substr($c->req->url->path, $route_len));
    return render_dir($c, $file) if $root->is_dir($file);
    return $c->mirrorcache->render_file($file) if $root->is_file($file);
    return undef;
}

sub render_dir {
    my $c     = shift;
    my $dir   = shift;
    my $route = $c->mc->route;

    if ( $c->req->url->path ne "/" && ! $c->req->url->path->trailing_slash ) {
        $c->redirect_to($c->req->url->path->trailing_slash(1));
        return undef;
    }

    my $files = $root->list_files($c->req->url->path, $dir);
    my $any = { inline => $dir_page, files => $files, cur_path => $dir };
    $c->render( %$any );
}

1;
