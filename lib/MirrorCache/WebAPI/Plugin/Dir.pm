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
use POSIX;
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
  % if (!$files || @$files == 0) {
  <tr>Folder is empty</tr>
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
    my $status = $c->param('status');

    my $path     = Mojo::Util::url_unescape(substr($c->req->url->path, $route_len));
    my $is_dir   = '/' eq substr($path, -1) ? 1 : 0;
    # trim trailing slash
    $path = substr($path,0,-1) if $is_dir && $path ne '/';
    my $schema   = $c->app->schema;
    unless ($root->is_remote) {
        unless ($status) {
            return render_dir($c, $path) if $root->is_dir($path);
            return $c->mirrorcache->render_file($path) if !$is_dir && $root->is_file($path);
        } else {
            return $c->render(text => 1) if $root->is_file($path) || $root->is_dir($path);
            return $c->render(status => 404, message => "path $path not found");
        }
        return undef;
    }
    # after this we are on remote root only
    # first try to render from DB, then check in $root
    my $rsFolder = $schema->resultset('Folder');

    unless ($is_dir) {
        my $f = Mojo::File->new($path);
        my $folder = $rsFolder->find({path => $f->dirname});
        unless ($folder) {
            $c->emit_event('mc_path_miss', $f->dirname) unless $folder;
        } else {
            my $file = $schema->resultset('File')->find({ name => $f->basename, folder_id => $folder->id });
            if ($file) {
                $c->mirrorcache->render_file($path);
            } else {
                $c->emit_event('mc_path_miss', $f->dirname);
            }
        }
    } else {
        my $folder   = $rsFolder->find({path => $path});
        return render_dir($c, $path, $rsFolder, $folder) if $folder && ($folder->db_sync_last);
    }

    my $tx = $c->render_later->tx;
    my $url = $c->app->mc->rootlocation;
    my $ua = Mojo::UserAgent->new;
    $ua->head_p($url . $path)->then(sub {
        my $code = shift->res->code;
        $c->emit_event('mc_debug', "head_p: $url, $path, $code, $is_dir");
        return $c->render(status => $code, text => "Error trying to check $url$path : $code") unless $code == 200 || $code == 301 || $code == 302;
        $c->emit_event('mc_debug', "head_p: $url, $path, $code, 2");
        return render_dir_remote($c, $path, $rsFolder) if $is_dir;

        $ua->head_p($url . $path . '/')->then(sub {
            return render_dir_remote($c, $path, $rsFolder) unless $code == 200 || $code == 301 || $code == 302;
            $c->mirrorcache->render_file($path);
        })->catch(sub {
            $c->mirrorcache->render_file($path);
            my $reftx = $tx;
            my $refua = $ua;
        })->timeout(2)->wait;
    })->catch(sub {
        $c->render(status => 404, text => Dumper(\@_)); # TODO proper code?
    })->timeout(2)->wait;
}

sub render_dir_remote { 
    my $c      = shift;
    my $dir    = shift;
    my $rsFolder = shift;

    my $job_id = $c->backstage->enqueue_unless_scheduled_with_parameter_or_limit('folder_sync', $dir);
    unless ($job_id) {
        $c->emit_event('mc_path_miss', $dir);
        return render_dir($c, $dir, $rsFolder) unless $job_id;
    }

    $c->minion->result_p($job_id)->then(sub {
        $c->emit_event('mc_debug', "promiseok: $job_id");
        render_dir($c, $dir, $rsFolder);
    })->catch(sub {
        $c->emit_event('mc_debug', "promisefail: $job_id " . Dumper(\@_));
        
        my $reason = $_;
        if ($reason eq 'Promise timeout') {
            return render_dir($c, $dir, $rsFolder);
        }
        $c->render(status => 500, text => Dumper($reason));
    })->timeout(10)->wait;
}

sub render_dir {
    my $c      = shift;
    my $dir    = shift;
    my $rsFolder = shift;
    my $folder = shift;

    # if ( $c->req->url->path ne "/" && ! $c->req->url->path->trailing_slash ) {
    #    return $c->redirect_to($c->req->url->path->trailing_slash(1));
    # }

    $c->emit_event('mc_debug', 'renderdir:' . $dir);
    my $schema = $c->app->schema;
    $rsFolder  = $schema->resultset('Folder') unless $rsFolder;
    $folder    = $rsFolder->find({path => $dir}) unless $folder;

    if ($folder) {
        if ($folder->db_sync_last) {
            my $files  = $root->list_files_from_db($c->req->url->path, $folder->id, $dir);
            my $any = { inline => $dir_page, files => $files, cur_path => $dir };
            return $c->render( %$any );
        } elsif (!$root->is_remote) { # for local root we can list content of directory
            my $files  = $root->list_files($c->req->url->path, $dir);
            my $any = { inline => $dir_page, files => $files, cur_path => $dir };
            return $c->render( %$any );
        }
   }
   my $pos = $rsFolder->get_db_sync_queue_position($dir);
   $c->render(status => 425, text => "Waiting in queue, at " . strftime("%Y-%m-%d %H:%M:%S", gmtime time) . " position: $pos");
}

1;
