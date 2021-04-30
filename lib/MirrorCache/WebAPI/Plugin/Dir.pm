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
use Mojolicious::Types;
use MirrorCache::Utils;

my $root;
my $dm;
my @top_folders;

sub register {
    my $self = shift;
    my $app = shift;

    $root = $app->mc->root;
    $dm   = $app->dm;

    if ($ENV{MIRRORCACHE_TOP_FOLDERS}) {
        @top_folders = split /[:,\s]+/, $ENV{MIRRORCACHE_TOP_FOLDERS};
    }

    $app->hook(
        before_dispatch => sub {
            return indx(shift);
        }
    );
    return $app;
}

sub indx {
    my $c = shift;
    my $reqpath = $c->req->url->path_query;
    if ($ENV{MIRRORCACHE_TOP_FOLDERS}) {
        my @found = grep { $reqpath =~ /^\/$_/ } @top_folders;
        return $c->redirect_to($dm->route . $reqpath) if @found;
    }

    return undef unless $dm->our_path($reqpath);
    # don't assign c earlier because it is relatively heavy operation
    $dm->reset($c);

    return $c if _redirect_geo($dm) ||
        _redirect_normalized($dm)   ||
        _render_stats($dm)          ||
        _local_render($dm)          ||
        _render_from_db($dm)        ||
        _guess_what_to_render($dm);
}

sub render_dir_remote {
    my $c      = shift;
    my $dir    = shift;
    my $rsFolder = shift;
    my $country  = shift || $c->dm->country;
    my $tx = $c->render_later->tx;

    my $job_id = 0;
    $job_id = $c->backstage->enqueue_unless_scheduled_with_parameter_or_limit('folder_sync', $dir);
    unless ($job_id > 0) {
        return _render_dir($c, $dir, $rsFolder);
    }

    $c->minion->result_p($job_id)->then(sub {
        $c->emit_event('mc_debug', "promiseok: $job_id");
        _render_dir($c, $dir, $rsFolder);
        my $reftx = $tx;
    })->catch(sub {
        $c->mmdb->emit_miss($dir, $country);
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

    $c->emit_event('mc_debug', 'renderdir:' . $dir);
    my $schema = $c->app->schema;
    $rsFolder  = $schema->resultset('Folder') unless $rsFolder;
    $folder    = $rsFolder->find({path => $dir}) unless $folder;

    return _render_dir_from_db($c, $folder->id, $dir) if $folder && $folder->db_sync_last;
    $c->mmdb->emit_miss($dir, $c->dm->country);
    return _render_dir_local($c, $dir) unless $root->is_remote; # just render files if we have them locally

    my $pos = $rsFolder->get_db_sync_queue_position($dir);
    return $c->render(status => 425, text => "Waiting in queue, at " . strftime("%Y-%m-%d %H:%M:%S", gmtime time) . " position: $pos");
}

sub _redirect_geo {
    my $c = $dm->c;
    # having both MIRRORCACHE_HEADQUARTER and MIRRORCACHE_REGION means that we are Subsidiary
    if ($ENV{MIRRORCACHE_HEADQUARTER} && $ENV{MIRRORCACHE_REGION}) {
        my $region = $dm->region;
        # redirect to the headquarter if country is not our region
        if ($region && (lc($ENV{MIRRORCACHE_REGION}) ne lc($region))) {
            $c->redirect_to($c->req->url->to_abs->scheme . "://" . $ENV{MIRRORCACHE_HEADQUARTER} . $dm->route . $dm->path_query) if $region && (lc($ENV{MIRRORCACHE_REGION}) ne lc($region));
            $c->stat->redirect_to_headquarter;
            return 1;
        }
    } elsif (my $region_url = $dm->has_subsidiary) {
        my $url = $c->req->url->to_abs->clone;
        $url->host($region_url->host);
        $url->port($region_url->port);
        $url->path_query($region_url->path . $url->path_query) if ($region_url->path);
        $c->redirect_to($url);
        $c->stat->redirect_to_region;
        return 1;
    }
    # MIRRORCACHE_ROOT_COUNTRY must be set only with remote root and when no mirrors should be used for the country
    return $root->render_file($c, $dm->path_query, 1) if $dm->root_country && !$dm->trailing_slash && $dm->root_country eq $dm->country && $root->is_file($dm->path) && !$dm->metalink;

    return undef;
}

sub _redirect_normalized {
    return $dm->c->redirect_to($dm->route . $dm->path . $dm->trailing_slash . $dm->query1) unless $dm->original_path eq $dm->path;
    return undef;
}

sub _render_stats {
    my $path = $dm->path;
    my $c = $dm->c;
    my $status = $c->param('status');
    return undef unless $status;
    return _render_stats_all($c, $path) if $status eq 'all';
    return _render_stats_recent($c, $path) if $status eq 'recent';
    return _render_stats_outdated($c, $path) if $status eq 'outdated';
    return _render_stats_not_scanned($c, $path) if $status eq 'not_scanned';
    return $c->render(text => 1) if ($root->is_file($path) || $root->is_dir($path));
    return $c->render(status => 404, text => "path $path not found");
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

sub _local_render {
    my ($path, $trailing_slash) = $dm->path;
    return undef if $root->is_remote || $dm->metalink;
    my $c = $dm->c;
    if ($root->is_dir($path)) {
        return $dm->redirect($dm->route . $path . '/') if !$trailing_slash && $path ne '/';
        return _render_dir($c, $path);
    }
    $c->mirrorcache->render_file($path) if !$trailing_slash && $root->is_file($path);
    return 1;
}

sub _render_from_db {
    my $c = $dm->c;
    my $schema = $c->schema;
    my ($path, $trailing_slash) = $dm->path;
    my $rsFolder = $schema->resultset('Folder');

    if (my $folder = $rsFolder->find_folder_or_redirect($path)) {
        return $dm->redirect($folder->{pathto}) if $folder->{pathto};
        # folder must have trailing slash, otherwise it will be a challenge to render links on webpage
        return $dm->redirect($dm->route . $path . '/') if !$trailing_slash && $path ne '/';
        return _render_dir($c, $path, $rsFolder) if ($folder->{db_sync_last});
    } elsif (!$trailing_slash && $path ne '/') {
        my $f = Mojo::File->new($path);
        my $parent_folder = $rsFolder->find({path => $f->dirname});
        my $file;
        $file = $schema->resultset('File')->find({ name => $f->basename, folder_id => $parent_folder->id }) if $parent_folder && !$trailing_slash;
        # folders are stored with trailing slash in file table, so they will not be selected here
        if ($file) {
            # regular file has trailing slash in db? That is probably incorrect, so let the root handle it
            return $root->render_file($c, $path . '/') if $trailing_slash;
            # find a mirror for it
            $c->mirrorcache->render_file($path);
            return 1;
        }
    }
}

sub _guess_what_to_render {
    my $c    = $dm->c;
    my $tx   = $c->render_later->tx;
    my ($path, $trailing_slash) = $dm->path;
    return $c->render(status => 425, text => 'Metalink is not ready') if !$root->is_remote && $dm->metalink;

    my $rootlocation = $root->location($c);
    my $url  = $rootlocation . $path;

    my $ua = Mojo::UserAgent->new->max_redirects(0);

    # try to guess if $path is a regular file or a directory
    # with added slash possible outcome can be:
    # - 404 - may mean it is a regular file or non-existing name (don't care => just redirect to root)
    # - 200 - means it is a folder - try to render
    # - redirected to another route => we must redirect it as well
    my $path1 = $path . '/';
    my $url1  = $url  . '/'; # let's check if it is a folder
    $ua->head_p($url1)->then(sub {
        my $res = shift->res;

        if ($res->is_error && $res->code ne 403) {
            $c->mmdb->emit_miss($path, $dm->country); # it is not a folder
        } else {
            if (!$res->is_redirect) {
                # folder must have trailing slash, otherwise it will be a challenge to render links on webpage
                return $dm->redirect($dm->route . $path . '/') if !$trailing_slash && $path ne '/';
                return render_dir_remote($c, $path);
            }

            # redirect on oneself
            if ($res->is_redirect && $res->headers) {
                my $location1 = $res->headers->location;
                if ($location1 && $path1 ne substr($location1, -length($path1))) {
                    my $i = rindex($location1, $rootlocation, 0);
                    if ($i ne -1) {
                        # remove trailing slash we added earlier
                        my $location = substr($location1, 0, -1);
                        if ($rootlocation eq substr($location, 0, length($rootlocation))) {
                            $location = substr($location, length($rootlocation));
                        }
                        return $dm->redirect($dm->route . $location . $trailing_slash)
                    }
                }
            }
        }
        # this should happen only if $url is a valid file or non-existing path
        return $root->render_file($c, $path . $trailing_slash);
    })->catch(sub {
        $c->mmdb->emit_miss($path, $dm->country);
        return $root->render_file($c, $path . $trailing_slash);
        my $reftx = $tx;
        my $refua = $ua;
    })->timeout(2)->wait;
}

sub _by_filename {
   $b->{dir} cmp $a->{dir} ||
   $a->{name} cmp $b->{name};
}

sub _get_ext {
    $_[0] =~ /\.([0-9a-zA-Z]+)$/ || return;
    return lc $1;
}
my $types = Mojolicious::Types->new;

sub _render_dir_from_db {
    my $c     = shift;
    my $id    = shift;
    my $dir   = shift;
    my @files;
    my @childrenfiles = $c->schema->resultset('File')->search({folder_id => $id});

    for my $child ( @childrenfiles ) {
        my $basename  = $child->name;
        my $size     = $child->size;
        $size        = MirrorCache::Utils::human_readable_size($size) if $size;
        my $mtime    = $child->mtime;
        $mtime       = strftime("%d-%b-%Y %H:%M:%S", gmtime($mtime)) if $mtime;

        my $is_dir    = '/' eq substr($basename, -1)? 1 : 0;
        my $encoded   = Encode::decode_utf8( './' . $basename );
        my $mime_type = $types->type( _get_ext($basename) || 'txt' ) || 'text/plain';

        push @files, {
            url   => $encoded,
            name  => $basename,
            size  => $size,
            type  => $mime_type,
            mtime => $mtime,
            dir   => $is_dir,
        };
    }
    my @items = sort _by_filename @files;
    return $c->render( 'dir', files => \@items, cur_path => $dir, folder_id => $id );
}

sub _render_dir_local {
    my $c     = shift;
    my $dir   = shift;
    my @files;
    my $filenames = $root->list_filenames($dir);

    for my $name ( @$filenames ) {
        my $basename = $name;
        # my $size     = $child->size;
        # $size        = MirrorCache::Utils::human_readable_size($size) if $size;
        # my $mtime    = $child->mtime;
        # mtime       = strftime("%d-%b-%Y %H:%M:%S", gmtime($mtime)) if $mtime;

        my $is_dir    = '/' eq substr($basename, -1)? 1 : 0;
        # my $encoded   = Encode::decode_utf8( './' . $basename );
        my $mime_type = $types->type( _get_ext($basename) || 'txt' ) || 'text/plain';

        push @files, {
            url   => './' . $basename,
            name  => $basename,
            size  => 0,
            type  => $mime_type,
            mtime => 0,
            dir   => $is_dir,
        };
    }
    my @items = sort _by_filename @files;
    return $c->render( 'dir', files => \@items, cur_path => $dir, folder_id => undef );
}


1;
