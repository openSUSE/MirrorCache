# Copyright (C) 2020-2022 SUSE LLC
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
use Sort::Versions;
use Time::Piece;
use Time::Seconds;
use Time::ParseDate;
use MirrorCache::Utils;
use MirrorCache::Datamodule;

my $root;
my $mc_config;
my @top_folders;

my $MCDEBUG = $ENV{MCDEBUG_DIR} // $ENV{MCDEBUG_ALL} // 0;

sub register {
    my $self = shift;
    my $app = shift;

    $root = $app->mc->root;
    $mc_config = $app->mc->config;

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

# Assume UserAgent of such pattern never lists directories and only needs to render files
my $PACKAGE_MANAGER_PATTERN = 'ZYpp .*|Debian APT.*|libdnf.*|osc.*';

sub indx {
    my $c = shift;
    my $reqpath = $c->req->url->path;

    my $top_folder;
    if ($ENV{MIRRORCACHE_TOP_FOLDERS}) {
        if ($reqpath =~ /^\/+$/) {
            $top_folder = '/';
        } else {
            my @found = grep { $reqpath =~ /^\/$_/ } @top_folders;
            $top_folder = $found[0] if @found;
        }
    }
    my $dm = MirrorCache::Datamodule->new->app($c->app);

    return undef unless $top_folder || $dm->our_path($reqpath);
    $dm->reset($c, $top_folder);

    return $c
      if _render_hashes($dm)
      || _render_small($dm)
      || _redirect_project_ln_geo($dm)
      || _redirect_normalized($dm)
      || _render_stats($dm)
      || _local_render($dm, 0) # check if we should render local
      || _render_from_db($dm)
      || _local_render($dm, 1); # check if we should render local when metalink cannot be provided

    if ($dm->agent =~ qr/$PACKAGE_MANAGER_PATTERN/) {
        my ($path, $trailing_slash) = $dm->path;
        return $root->render_file($dm, $path) unless $trailing_slash;
    }

    my $tx = $c->render_later->tx;
    my $rendered;
    my $handle_error = sub {
        return if $rendered;
        $rendered = 1;
        my @reason = @_;
        my $reason = scalar(@reason)? Dumper(@reason) : 'unknown';
        $c->render(json => {error => $reason}, status => 500) ;
    };

    my $p = Mojo::Promise->new;
    $p->then(sub {
        $rendered = _guess_what_to_render($dm);
    })->catch($handle_error);
    $p->resolve;
}

# render_dir_remote tries to render dir when RootRemote cannot find it in DB

my $RENDER_DIR_REMOTE_PROMISE_TIMEOUT = int($ENV{MIRRORCACHE_RENDER_DIR_REMOTE_PROMISE_TIMEOUT}  // 15) // 15;

sub render_dir_remote {
    my $dm       = shift;
    my $dir      = shift;
    my $c  = $dm->c;
    my $tx = $c->render_later->tx;

    my $job_id = 0;
    $job_id = $c->backstage->enqueue_unless_scheduled_with_parameter_or_limit('folder_sync', $dir);
    # if scheduling didn't happen - let's try to render anyway
    if ($job_id < 1) {
        return _render_dir($dm, $dir);
    }

    my $handle_error = sub {
        my $reason = shift;
        if ($reason eq 'Promise timeout') {
            return _render_dir($dm, $dir);
        }
        $c->render(status => 500, text => Dumper($reason));
        my $reftx = $tx;
    };

    $c->minion->result_p($job_id)->timeout($RENDER_DIR_REMOTE_PROMISE_TIMEOUT)->catch($handle_error)->then(sub {
        $c->emit_event('mc_debug', "promiseok: $job_id");
        _render_dir($dm, $dir);
        my $reftx = $tx;
    })->timeout($RENDER_DIR_REMOTE_PROMISE_TIMEOUT)->catch($handle_error)->timeout($RENDER_DIR_REMOTE_PROMISE_TIMEOUT)->wait;
}

sub _render_dir {
    my $dm     = shift;
    my $dir    = shift;
    my $rsFolder = shift;
    my $c = $dm->c;

    my $folder_id = $dm->folder_id;
    unless ($folder_id) {
        $rsFolder  = $c->app->schema->resultset('Folder') unless $rsFolder;
        if (my $folder = $rsFolder->find({path => $dm->root_subtree . $dir})) {
            $folder_id = $folder->id;
            $dm->folder_id($folder_id);
            $dm->folder_sync_last($folder->sync_last);
            $dm->file_id(-1);
        }
    }
    return $c->render( 'browse', route => $dm->route, cur_path => $dir, folder_id => $folder_id, re_pattern => $dm->re_pattern ) if !$dm->json && $dm->browse;

    return _render_dir_local($dm, $folder_id, $dir) unless $root->is_remote; # just render files if we have them locally

    $c->stat->redirect_to_root($dm, 0) unless $folder_id && $dm->folder_sync_last;
    return _render_dir_from_db($dm, $folder_id, $dir) if $folder_id && $dm->folder_sync_last;

    my $pos = $rsFolder->get_sync_queue_position($dir);
    return $c->render(status => 425, text => "Waiting in queue, at " . strftime("%Y-%m-%d %H:%M:%S", gmtime time) . " position: $pos");
}

# this combines similar checks for redirecting as specified in DB links and projects, as well as subsidiaries
sub _redirect_project_ln_geo {
    my $dm = shift;
    my ($path, $trailing_slash) = $dm->path;

    my $c = $dm->c;
    # each project may have a redirect defined in DB, so all requests are redirected for it
    unless ($trailing_slash) {
        my $redirect = $c->mcproject->redirect($path, $dm->region);
        if ($redirect) {
            $dm->redirect($dm->scheme . '://' . $redirect . $path);
            $c->stat->redirect_to_region($dm);
            return 1;
        }

        $c->log->error('pedantic: ' . ($dm->pedantic // 'undef')) if $MCDEBUG;
        if ($path =~ m/.*(Media|Current)\.iso(\.sha256(\.asc)?)?/ && $dm->pedantic) {
            my $ln = $root->detect_ln_in_the_same_folder($path);
            $c->log->error("ln for $path : " . ($ln // 'null')) if $MCDEBUG;
            if ($ln) {
                # redirect to the symlink
                $c->log->error('redirect detected: ' . $ln) if $MCDEBUG;
                $dm->redirect($dm->route . $ln);
                return 1;
            }
        }
    }
    return undef if $trailing_slash || $path eq '/' || $dm->mirrorlist;
    return undef if $dm->must_render_from_root;
    my $subsidiary = $c->subsidiary;
    my $url = $subsidiary->has($dm, $c->req->url);
    if ($url) {
        $c->redirect_to($url);
        $c->stat->redirect_to_region($dm);
        return 1;
    }
    # MIRRORCACHE_ROOT_COUNTRY must be set only with remote root and when no mirrors should be used for the country
    return $root->render_file($dm, $path, 1) if $dm->root_country && !$dm->trailing_slash && $dm->root_country eq $dm->country && $root->is_file($dm->_path) && !$dm->extra;

    return undef;
}

sub _redirect_normalized {
    my $dm = shift;
    return undef if $dm->accept;
    my ($path, $trailing_slash, $original_path) = $dm->path;
    return undef if $path eq '/';
    $path = $path . '.metalink' if $dm->metalink;
    $path = $path . '.meta4'    if $dm->meta4;
    return $dm->c->redirect_to($dm->route . $path . $trailing_slash . $dm->query1) unless $original_path eq $path || ($dm->extra && !$dm->metalink && !$dm->meta4);
    return undef;
}

sub _render_stats {
    my $dm = shift;
    my ($path, undef) = $dm->path;
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
    my $dm     = shift;
    my $accept = shift;
    return undef if $dm->extra && (!$accept || !$dm->accept_all);
    my ($path, $trailing_slash) = $dm->path;
    # we can just render top folders
    return _render_top_folders($dm) if $ENV{MIRRORCACHE_TOP_FOLDERS} && $path eq '/';
    return $root->render_file_if_nfs($dm, $path) if $root->is_remote;

    if ($root->is_dir($path)) {
        return $dm->redirect($dm->route . $path . '/') if !$trailing_slash && $path ne '/';
        return _render_dir($dm, $path);
    }
    $dm->c->mirrorcache->render_file($path, $dm) if !$trailing_slash && $root->is_file($path);
    return 1;
}

sub _render_from_db {
    my $dm = shift;
    my $c = $dm->c;
    my $schema = $c->schema;
    my ($path, $trailing_slash) = $dm->path;
    my $rsFolder = $schema->resultset('Folder');

    my $file_pattern_in_folder = $trailing_slash && ($dm->regex || $dm->glob) && ($dm->metalink || $dm->meta4 || $dm->mirrorlist);
    $c->log->error($c->dumper('$file_pattern_in_folder', $file_pattern_in_folder)) if $MCDEBUG;
    if ( (!$trailing_slash && $path ne '/') || $file_pattern_in_folder ) {
        my $f = Mojo::File->new($path);
        my $dirname = ($file_pattern_in_folder? $path : $f->dirname);
        $dirname = $root->realpath($dirname);
        $dirname = $dm->root_subtree . ($file_pattern_in_folder? $path : $f->dirname) unless $dirname;
        $c->log->error($c->dumper('dirname:', $dirname)) if $MCDEBUG;
        if (my $parent_folder = $rsFolder->find({path => $dirname})) {
            my $realpath_subtree = $root->realpath($dm->root_subtree . ($file_pattern_in_folder? $path : $f->dirname)) // $dirname;
            if ($dirname eq $realpath_subtree) {
                if ($dirname eq $f->dirname || $file_pattern_in_folder) {
                    $dm->folder_id($parent_folder->id);
                    $dm->folder_sync_last($parent_folder->sync_last);
                    $dm->folder_scan_last($parent_folder->scan_last);
                }
            } else {
                my $another_folder = $rsFolder->find({path => $dm->root_subtree . $f->dirname});
                $c->log->error($c->dumper('another_folder:', $another_folder)) if $MCDEBUG;
                return undef unless $another_folder; # nothing found, proceed to _guess_what_to_render
            }
            my $xtra = '';
            $xtra = '.zsync' if $dm->zsync && !$dm->accept_zsync;
            my $file;
            $c->log->error($c->dumper('parent_folder:', $parent_folder->path)) if $MCDEBUG;
            $file = $schema->resultset('File')->find_with_hash($parent_folder->id, $f->basename, $xtra, $dm->regex, $dm->glob_regex) if $parent_folder;
            $c->log->error($c->dumper('file:', $f->basename, $file)) if $MCDEBUG;

            # folders are stored with trailing slash in file table, so they will not be selected here
            if ($file) {
                my $filename = $file->{name} if $file;
                if ($dm->zsync && !$dm->accept_zsync && $file && $filename && '.zsync' eq substr $filename, -length('.zsync')) {
                    $dm->zsync(0);
                    $dm->accept_all(1);
                    $dm->_path($dm->path . '.zsync');
                    $path = $path . '.zsync';
                }

                if ($file->{target}) {
                    # redirect to the symlink
                    $dm->redirect($dm->route . $dirname . '/' . $file->{target});
                } else {
                    $dm->file_id($file->{id});
                    # find a mirror for it
                    $c->mirrorcache->render_file($path, $dm, $file);
                }
                return 1;
            }
        }
    } elsif (my $folder = $rsFolder->find_folder_or_redirect($dm->root_subtree . $path)) {
        $c->log->error('found redirect : ', $folder->{pathto}) if $MCDEBUG && $folder->{pathto};
        return $dm->redirect($folder->{pathto}) if $folder->{pathto};
        # folder must have trailing slash, otherwise it will be a challenge to render links on webpage
        $dm->folder_id($folder->{id});
        $dm->folder_sync_last($folder->{sync_last});
        $dm->folder_scan_last($folder->{scan_last});
        $dm->file_id(-1);
        return _render_dir($dm, $path, $rsFolder, $folder) if ($folder->{sync_last});
    }
    return undef;
}

sub _guess_what_to_render {
    my $dm   = shift;
    my $c    = $dm->c;
    my $tx   = $c->render_later->tx;
    my ($path, $trailing_slash) = $dm->path;

    if ($dm->extra) {
        $c->log->error('guess what to render extra : ', $dm->extra) if $MCDEBUG;
        return $root->render_file($dm, $path) if $dm->accept_all && !$trailing_slash;
        # the file is unknown, we cannot show generate meither mirrorlist or metalink
        my $res = $c->render(status => 425, text => "The file is unknown, retry later");
        # log miss here even thoough we haven't rendered anything
        $c->stat->redirect_to_root($dm, 0);
        return $res;
    }

    my $rootlocation = $root->location;
    my $url  = $rootlocation . $path;

    my $ua = Mojo::UserAgent->new->max_redirects(0);

    # try to guess if $path is a regular file or a directory
    # with added slash possible outcome can be:
    # - 404 - may mean it is a regular file or non-existing name (don't care => just redirect to root)
    # - 200 - means it is a folder - try to render
    # - redirected to another route => we must redirect it as well
    my $path1 = $path . '/';
    my $url1  = $url  . '/'; # let's check if it is a folder
    my $redirect;
    $ua->head_p($url1, {'User-Agent' => 'MirrorCache/guess_what_to_render'})->then(sub {
        my $res = shift->res;

        if (!$res->is_error || $res->code eq 403) {
            if (!$res->is_redirect) {
                # folder must have trailing slash, otherwise it will be a challenge to render links on webpage
                return $dm->redirect($dm->route . $path . '/') if !$trailing_slash && $path ne '/';
                return render_dir_remote($dm, $path);
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
                        $c->log->error('redirect guessed: ' . $location . $trailing_slash) if $MCDEBUG;
                        $redirect = 1;
                        return $dm->redirect($dm->route . $location . $trailing_slash);
                    }
                }
            }
        }
        # this should happen only if $url is a valid file or non-existing path
        return $root->render_file($dm, $path . $trailing_slash);
    })->catch(sub {
        $root->render_file($dm, $path . $trailing_slash);
        my $msg = "Error while guessing how to render $url: ";
        if (1 == scalar(@_)) {
            $msg = $msg . $_[0];
        } else {
            $msg = $msg . Dumper(@_);
        }
        $c->app->log->fatal($msg); # it is not fatal, but needed in production log
        my $reftx = $tx;
        my $refua = $ua;
    })->timeout(5)->then(sub {
        $c->backstage->enqueue_unless_scheduled_with_parameter_or_limit('folder_sync', $path) if $redirect;
    })->wait;
}

sub _by_filename {
   versioncmp(lc($b->{dir} // ''),  lc($a->{dir} // '')) ||
   versioncmp(lc($a->{name} // ''), lc($b->{name} // ''));
}

my %folderDesc = (
    "openSUSE" => {
        "/" => {
            "debug/"        => "debugging packages for openSUSE distributions",
            "distribution/" => "Leap packages, sources and images",
            "factory/"      => "Link to tumbleweed/",
            "history/"      => "former releases of Tumbleweed packages",
            "ports/"        => "openSUSE distributions for different architectures",
            "repositories/" => "packages and images created with the Open Build Service",
            "source/"       => "source packages of openSUSE distributions",
            "tumbleweed/"   => "Tumbleweed packages, sources and images",
            "update/"       => "updates for packages in openSUSE distributions",
        },
    },
);

sub _render_top_folders {
    my $dm  = shift;
    my $dir = '/';
    my $c   = $dm->c;
    my @files;
    my $json = $dm->json;

    for my $basename ( @top_folders ) {
        my $basename2 = "$basename/";
        if ($json) {
            push @files, {
                name  => $basename2,
                desc  => $folderDesc{$c->mcbranding}{$dir}{$basename2},
            };
            next;
        }
        my $encoded   = Encode::decode_utf8( './' . $basename2 );

        push @files, {
            url   => $encoded,
            name  => $basename2,
            dir   => 1,
            desc  => $folderDesc{$c->mcbranding}{$dir}{$basename2},
        };
    }
    my @items = sort _by_filename @files;
    return $c->render( json => { data => \@items } ) if $dm->jsontable;
    return $c->render( json => \@items) if $json;
    return $c->render( 'dir', files => \@items, route => $dm->route, cur_path => $dir, folder_id => undef );
}

sub _render_dir_from_db {
    my $dm  = shift;
    my $id  = shift;
    my $dir = shift;
    my $c   = $dm->c;
    my $json = $dm->json;

    return $c->render( 'browse', route => $dm->route, cur_path => $dir, folder_id => $id, re_pattern => $dm->re_pattern ) if !$json && $dm->browse;

    my @files;
    my $childrenfiles = $c->schema->resultset('File')->find_with_regex($id, $dm->glob_regex, $dm->regex);

    for my $file_id ( keys %$childrenfiles ) {
        my $child = $childrenfiles->{$file_id};
        my $basename = $child->{name};
        my $size     = $child->{size};
        my $mtime    = $child->{mtime};
        my $desc     = $folderDesc{$c->mcbranding}{$dir}{$basename};
        if ($json) {
            push @files, {
                name  => $basename,
                size  => $size,
                mtime => $mtime,
            };
        } else {
            $size        = MirrorCache::Utils::human_readable_size($size) if $size;
            $mtime       = strftime("%d-%b-%Y %H:%M", gmtime($mtime)) if $mtime;

            my $is_dir    = '/' eq substr($basename, -1)? 1 : 0;
            my $encoded   = Encode::decode_utf8( './' . $basename );
            my $mime_type = $dm->mime || 'text/plain';

            push @files, {
                url   => $encoded,
                name  => $basename,
                size  => $size,
                type  => $mime_type,
                mtime => $mtime,
                dir   => $is_dir,
            };
        }
        $files[-1]->{desc} = $desc if $desc;
    }
    my @items = sort _by_filename @files;
    return $c->render( json => { data => \@items } ) if $dm->jsontable;
    return $c->render( json => \@items) if $json;
    return $c->render( 'dir', files => \@items, route => $dm->route, cur_path => $dir, folder_id => $id );
}

sub _render_dir_local {
    my $dm  = shift;
    my $id  = shift;
    my $dir = shift;
    my $c   = $dm->c;
    my $json = $dm->json;
    return $c->render( 'browse', route => $dm->route, cur_path => $dir, folder_id => $id, re_pattern => $dm->re_pattern ) if !$json && $dm->browse;

    my @files;

    my $realpath = $root->realpath($dir);
    $realpath =  $dm->root_subtree . $dir unless $realpath;
    my $files = $root->list_files($realpath, $dm->glob_regex, $dm->regex);

    for my $f ( @$files ) {
        my $basename = $f->basename;
        my $stat     = $f->stat;
        $basename = $basename . '/' if $stat && -d $stat;
        my $size     = $stat->size if $stat;
        my $mtime    = $stat->mtime if $stat;
        my $desc     = $folderDesc{$c->mcbranding}{$dir}{$basename};
        if ($json) {
            push @files, {
                name  => $basename,
                size  => $size,
                mtime => $mtime,
            };
        } else {
            $size        = MirrorCache::Utils::human_readable_size($size) if $size;
            $mtime       = strftime("%d-%b-%Y %H:%M", gmtime($mtime)) if $mtime;

            my $is_dir    = '/' eq substr($basename, -1)? 1 : 0;
            my $encoded   = Encode::decode_utf8( './' . $basename );
            my $mime_type = $dm->mime || 'text/plain';

            push @files, {
                url   => $encoded,
                name  => $basename,
                size  => $size,
                type  => $mime_type,
                mtime => $mtime,
                dir   => $is_dir,
            };
        }
        $files[-1]->{desc} = $desc if $desc;
    }
    my @items = sort _by_filename @files;
    return $c->render( json => { data => \@items } ) if $dm->jsontable;
    return $c->render( json => \@items) if $json;
    return $c->render( 'dir', files => \@items, route => $dm->route, cur_path => $dir, folder_id => $id );
}

my $SMALL_FILE_SIZE = int($ENV{MIRRORCACHE_SMALL_FILE_SIZE} // 0);
my $ROOT_NFS = $ENV{MIRRORCACHE_ROOT_NFS};

sub _render_small {
    return undef unless $SMALL_FILE_SIZE && ($ROOT_NFS || !$root->is_remote );
    my $dm = shift;
    $dm->_init_path;
    return undef if ($dm->metalink && !$dm->accept_all) || ($dm->meta4 && !$dm->accept_all) || $dm->mirrorlist || $dm->zsync;
    my ($path, undef) = $dm->path;
    my $full;
    return $root->render_file_if_small($dm, $path, $SMALL_FILE_SIZE) unless $ROOT_NFS;
    $full = $ROOT_NFS . $path;
    my $size;
    eval { $size = -s $full if -f $full; };
    return undef unless (defined $size) && $size <= $SMALL_FILE_SIZE;
    my $c = $dm->c;
    $c->render_file(filepath => $full, content_type => $dm->mime);
    return 1;
}

sub _render_hashes {
    my $dm = shift;
    my $c = $dm->c;
    return undef unless defined($c->param('hashes'));
    my ($path, undef) = $dm->path;

    my $time_constraint;
    if (defined $c->param("since") && $c->param("since")) {
        $time_constraint = parsedate($c->param("since"), PREFER_PAST => 1, DATE_REQUIRED => 1);
        return $c->render(status => 404, text => $c->param('since') . ' is not a valid date') unless $time_constraint;

        $time_constraint = localtime($time_constraint);
    }

    my $schema   = $c->app->schema;
    my $folder   = $schema->resultset('Folder')->find({path => $path});

    if ($folder) {
        my $rsHash    = $schema->resultset('Hash');
        my $folder_id = $folder->id;
        return $c->render(json => $rsHash->hashes_since($folder_id, $time_constraint));
    };

    return $c->render(status => 404, text => "path $path not found") unless $root->is_dir($path);

    my $job_id = $c->backstage->enqueue_unless_scheduled_with_parameter_or_limit('folder_sync', $path);
    # if scheduling didn't happen - return 404 so far
    return $c->render(status => 404, text => "path $path not found") if $job_id < 1;
    return $c->render(status => 201, text => '[]');
}

1;
