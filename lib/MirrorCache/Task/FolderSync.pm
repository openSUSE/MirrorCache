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

package MirrorCache::Task::FolderSync;
use Mojo::Base 'Mojolicious::Plugin';

use DateTime;

sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(folder_sync => sub { _sync($app, @_) });
}

sub _sync {
    my ($app, $job, $path) = @_;
    return $job->fail('Empty path is not allowed') unless $path;
    return $job->fail('Trailing slash is forbidden') if '/' eq substr($path,-1) && $path ne '/';

    my $minion = $app->minion;
    return $job->finish('Previous folder sync job is still active')
        unless my $guard = $minion->guard('folder_sync' . $path, 360);

    my $schema = $app->schema;
    my $root   = $app->mc->root;
    return $job->finish("$path is not a dir") unless $root->is_dir($path);

    my $localfiles = $app->mc->root->list_filenames($path);
    my $folder = $schema->resultset('Folder')->find({path => $path});
    unless ($folder) {
        $folder = $schema->resultset('Folder')->find_or_create({path => $path});
        foreach my $file (@$localfiles) {
            $file = $file . '/' if !$root->is_remote && $root->is_dir("$path/$file") && $path ne '/';
            $file = $file . '/' if !$root->is_remote && $root->is_dir("$path$file") && $path eq '/';
            $schema->resultset('File')->create({folder_id => $folder->id, name => $file});
        }
        $job->note(created => $path, count => scalar(@$localfiles));
        $folder->update({db_sync_last => $schema->storage->datetime_parser->format_datetime(DateTime->now())}, {db_sync_priority => 10});
        $app->emit_event('mc_path_scan_complete', {path => $path, tag => $folder->id});
        $minion->enqueue('mirror_scan' => [$path] => {priority => 10});
        return;
    };
    return $job->fail("Couldn't create folder $path") unless $folder && $folder->id;

    my $folder_id = $folder->id;
    my @dbfiles = ();
    my %dbfileids = ();
    for my $file ($schema->resultset('File')->search({folder_id => $folder_id})) {
        my $basename = $file->name;
        # next unless $basename && -f $localdir . $basename; # skip deleted files for now
        next unless $basename;
        push @dbfiles, $basename;
        $dbfileids{$basename} = $file->id;
    }

    my $cnt = 0;
    for my $file (@$localfiles) {
        next if $dbfileids{$file}; # || '/' eq substr($file, -1);
        $file = $file . '/' if !$root->is_remote && $root->is_dir("$path/$file") && $path ne '/';
        $file = $file . '/' if !$root->is_remote && $root->is_dir("$path$file") && $path eq '/';
        $schema->resultset('File')->create({folder_id => $folder->id, name => $file});
        $cnt = $cnt + 1;
    }
    $schema->storage->datetime_parser;
    $folder->update({db_sync_last => $schema->storage->datetime_parser->format_datetime(DateTime->now())}, {db_sync_priority => 10});
    $job->note(updated => $path, count => $cnt);
    $minion->enqueue('mirror_scan' => [$path] => {priority => 10}) if $cnt;
    $app->emit_event('mc_path_scan_complete', {path => $path, tag => $folder->id});
}

1;
