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

package MirrorCache::Task::FolderTree;
use Mojo::Base 'Mojolicious::Plugin';

# Logic inside FolderSync may take some time to add thousands of files for each folder
# So FolderTree job will just create new folders and request sync jobs for them
# Additionally if we don't create files inside FolderTree - there will be no contention 
# between FolderSync and FolderTree jobs

sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(folder_tree => sub { _sync($app, @_) });
}

my $MAX_DEPTH=6;

sub _sync {
    my ($app, $job, $path, $recurs) = @_;
    return $job->fail('Empty path is not allowed') unless $path;
    return $job->fail('Trailing slash is forbidden') if '/' eq substr($path,-1) && $path ne '/';

    my $minion = $app->minion;
    return $job->finish('Previous folder tree job is still active')
        unless my $guard = $minion->guard('folder_tree' . $path, 360);

    my $schema = $app->schema;
    my $root   = $app->mc->root;
    $job->note($path => 1);

    my $realpath = $root->realpath($path);
    $realpath = $path unless $realpath;
    if ($realpath ne $path) {
        $job->note($realpath => 1);
    }
    return $job->finish('Not a directory') unless ($root->is_dir($realpath));
    my $rsFolder = $schema->resultset('Folder');

    _recurs($job, $root, $rsFolder, $path, $MAX_DEPTH);
}

sub _recurs {
    my ($job, $root, $rs, $path, $depth) = @_;
    return undef unless $depth && $depth > 0;
    $depth--;
    my $realpath = $root->realpath($path);
    $realpath = $path unless $realpath;
    if ($realpath ne $path) {
        $job->note($realpath => 1);
    }
    $rs->request_sync($realpath);

    my $sub = sub {
        my ($file, $size, $mmode, $mtime) = @_;
        my $is_dir = 0;
        if ($root->is_remote) {
            if ($mmode) {
                $is_dir = 1 if $mmode < 1000;
            } else {
                $is_dir = 1 if '/' eq chop $file;
            }
        } else {
            my $path1 = $realpath;
            $path1 = $path1 . '/' unless $realpath eq '/';
            $is_dir = 1 if $root->is_dir($path1 . $file);
        }
        _recurs($job, $root, $rs, $realpath . '/' . $file, $depth) if $is_dir;
    };

    eval {
        $root->foreach_filename($realpath, $sub);
        1;
    } or return $job->note($path => $@);
}

1;
