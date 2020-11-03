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

use POSIX;
use Data::Dumper;

my $root;
my @top_folders;

sub register {
    my $self = shift;
    my $app = shift;

    $root = $app->mc->root;
    my $route = $app->mc->route;
    my $route_len = length($route);

    if ($ENV{MIRRORCACHE_TOP_FOLDERS}) {
        @top_folders = split /[:,\s]+/, $ENV{MIRRORCACHE_TOP_FOLDERS};
    }

    $app->hook(
        before_dispatch => sub {
            return indx(shift, $route, $route_len);
        }
    );
    return $app;
}

sub indx {
    my ($c, $route, $route_len) = @_;
    my $reqpath = $c->req->url->path;
    if ($ENV{MIRRORCACHE_TOP_FOLDERS}) {
        my @found = grep { $reqpath =~ /^\/$_/ } @top_folders;

        return $c->redirect_to($route . $reqpath) if @found;
    }
    return undef unless 0 eq rindex($reqpath, $route, 0);
    my $status = $c->param('status');

    my $path     = Mojo::Util::url_unescape(substr($reqpath, $route_len));
    my $is_dir   = '/' eq substr($path, -1) ? 1 : 0;
    # trim trailing slash
    $path = "/" unless $path;
    $path = substr($path,0,-1) if $is_dir && $path ne '/';
    my $normalized_path = _normalize_path($path);
    return $c->redirect_to($route . $normalized_path) unless $normalized_path eq $path;
    if ($status) {
        return _render_stats_all($c, $path) if $status eq 'all';
        return _render_stats_recent($c, $path) if $status eq 'recent';
        return _render_stats_outdated($c, $path) if $status eq 'outdated';
        return _render_stats_not_scanned($c, $path) if $status eq 'not_scanned';
        return $c->render(text => 1) if $root->is_file($path) || $root->is_dir($path);
        return $c->render(status => 404, message => "path $path not found");
    }

    my $schema   = $c->app->schema;
    unless ($root->is_remote) {
        return _render_dir($c, $path) if $root->is_dir($path);
        return $c->mirrorcache->render_file($path) if !$is_dir && $root->is_file($path);
        return undef;
    }
    # after this we are on remote root only
    # first try to render from DB, then check in $root
    my $rsFolder = $schema->resultset('Folder');
    my $folder = $rsFolder->find({path => $path});

    if ($folder) {
        return _render_dir($c, $path, $rsFolder, $folder) if ($folder->db_sync_last);
    } else {
        my $f = Mojo::File->new($path);
        $folder = $rsFolder->find({path => $f->dirname});
        my $file;
        $file = $schema->resultset('File')->find({ name => $f->basename, folder_id => $folder->id }) if $folder;
        return $c->mirrorcache->render_file($path) if $file;
        $c->mmdb->emit_miss($f->dirname);
    }
    # Now try to get content asynchronically
    my $tx = $c->render_later->tx;
    my $url = $c->app->mc->rootlocation;
    my $ua = Mojo::UserAgent->new;
    $ua->head_p($url . $path)->then(sub {
        my $code = shift->res->code;
        $c->emit_event('mc_debug', "head_p: $url, $path, $code, $is_dir");
        return $c->render(status => $code, text => "Error trying to check $url$path : $code") unless $code == 200 || $code == 301 || $code == 302;
        $c->emit_event('mc_debug', "head_p: $url, $path, $code, 2");

        my $redir = $root->is_self_redirect($path);
        return $c->redirect_to($route . $redir) if $redir;

        return render_dir_remote($c, $path, $rsFolder) if $is_dir;

        $ua->head_p($url . $path . '/')->then(sub {
            $code = shift->res->code;
            return render_dir_remote($c, $path, $rsFolder) if $code == 200 || $code == 301 || $code == 302;
            $c->mirrorcache->render_file($path);
        })->catch(sub {
            $c->mirrorcache->render_file($path);
            my $reftx = $tx;
            my $refua = $ua;
        })->timeout(2)->wait;
    })->catch(sub {
        $c->render(status => 404, text => Dumper(\@_)); # TODO proper code?
    })->timeout(12)->wait;
}

sub render_dir_remote { 
    my $c      = shift;
    my $dir    = shift;
    my $rsFolder = shift;
    my $tx = $c->render_later->tx;
    my $country  = $c->mmdb->country;

    my $job_id = 0;
    $job_id = $c->backstage->enqueue_unless_scheduled_with_parameter_or_limit('folder_sync', $dir, $country);
    unless ($job_id > 0) {
        $c->mmdb->emit_miss($dir, $country);
        return _render_dir($c, $dir, $rsFolder);
    }

    $c->minion->result_p($job_id)->then(sub {
        $c->emit_event('mc_debug', "promiseok: $job_id");
        _render_dir($c, $dir, $rsFolder);
        my $reftx = $tx;
    })->catch(sub {
        $c->emit_event('mc_debug', "promisefail: $job_id " . Dumper(\@_));
        
        my $reason = $_;
        if ($reason eq 'Promise timeout') {
            return _render_dir($c, $dir, $rsFolder);
        }
        $c->render(status => 500, text => Dumper($reason));
        my $reftx = $tx;
    })->timeout(5)->wait;
}

sub _render_dir {
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
            return $c->render( 'dir', files => $files, cur_path => $dir, folder_id => $folder->id );
        }
    }

    if (!$root->is_remote) { # for local root we can list content of directory
        my $files  = $root->list_files($c->req->url->path, $dir);
        return $c->render( 'dir', files => $files, cur_path => $dir, folder_id => "" );
    }

    my $pos = $rsFolder->get_db_sync_queue_position($dir);
    $c->render(status => 425, text => "Waiting in queue, at " . strftime("%Y-%m-%d %H:%M:%S", gmtime time) . " position: $pos");
}

sub _render_stats_all {
    my $c      = shift;
    my $dir    = shift;

    my $schema   = $c->app->schema;
    my $rsFolder = $schema->resultset('Folder');

    return $c->render(json => $rsFolder->stats_all($dir));
}
    
sub _render_stats_recent {
    my $c      = shift;
    my $dir    = shift;

    my $schema   = $c->app->schema;
    my $rsFolder = $schema->resultset('Folder');

    return $c->render(json => $rsFolder->stats_recent($dir));
}

sub _render_stats_outdated {
    my $c      = shift;
    my $dir    = shift;

    my $schema   = $c->app->schema;
    my $rsFolder = $schema->resultset('Folder');

    return $c->render(json => $rsFolder->stats_outdated($dir));
}

sub _render_stats_not_scanned {
    my $c      = shift;
    my $dir    = shift;

    my $schema   = $c->app->schema;
    my $rsFolder = $schema->resultset('Folder');

    return $c->render(json => $rsFolder->stats_not_scanned($dir));
}

# remove . and .. replace // from path to make sure DB has no duplicates
sub _normalize_path {
    my $path = shift;
    my @c = reverse split m@/@, $path;
    my @c_new;
    while (@c) {
        my $component = shift @c;
        next unless length($component);
        if ($component eq '.') { next; }
        if ($component eq '..') { shift @c; next }
        push @c_new, $component;
    }
    return '/'.join('/', reverse @c_new);
}

1;
