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

package MirrorCache::Task::FolderScan;
use Mojo::Base 'Mojolicious::Plugin';

use DateTime;
use Digest::MD5;
use Mojo::UserAgent;
use Mojo::Util ('trim');

sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(folder_scan => sub { _scan($app, @_) });
}

sub _scan {
    my ($app, $job, $path) = @_;

    my $schema = $app->schema;
    my $minion = $app->minion;

    my $localdir = $app->mc->root($path);
    my $localfiles = Mojo::File->new($localdir)->list->map( 'basename' )->to_array;
    my $guard = $app->minion->guard('scan_folder' . $path, 60);
    my $folder = $schema->resultset('Folder')->find({path => $path});
    unless ($folder) {
        $folder = $schema->resultset('Folder')->find_or_create({path => $path});
        foreach my $file (@$localfiles) {
            $schema->resultset('File')->create({folder_id => $folder->id, name => $file});
        }
        $job->note(created => $path, count => scalar(@$localfiles));
        $app->emit_event('mc_path_scan_complete', {path => $path, tag => $folder->id});
        $minion->enqueue('mirror_scan' => [$path] => {priority => 10});
        return;
    };
    return $job->fail("Couldnt find folder $path") unless $folder && $folder->id;

    my $folder_id = $folder->id;
    my @dbfiles = ();
    my %dbfileids = ();
    for my $file ($schema->resultset('File')->search({folder_id => $folder_id})) {
        my $basename = $file->name;
        next unless $basename && -f $localdir . $basename; # skip deleted files for now
        push @dbfiles, $basename;
        $dbfileids{$basename} = $file->id;
    }

    my $cnt = 0;
    for my $file (@$localfiles) {
        next if $dbfileids{$file};
        $schema->resultset('File')->create({folder_id => $folder->id, name => $file});
        $cnt = $cnt + 1;
    }
    $job->note(updated => $path, count => $cnt);
    $minion->enqueue('mirror_scan' => [$path] => {priority => 10});
    $app->emit_event('mc_path_scan_complete', {path => $path, tag => $folder->id});
}

1;
