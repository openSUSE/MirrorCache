# Copyright (C) 2020-2024 SUSE LLC
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
use MirrorCache::Utils 'datetime_now';

use Directory::Scanner::OBSReleaseInfo;

my $HASHES_COLLECT = $ENV{MIRRORCACHE_HASHES_COLLECT} // 0;
my $HASHES_IMPORT  = $ENV{MIRRORCACHE_HASHES_IMPORT} // 0;
my $HASHES_QUEUE   = $ENV{MIRRORCACHE_HASHES_QUEUE} // 'hashes';
my $SCAN_MTIME_DIFF= $ENV{MIRRORCACHE_SCAN_MTIME_DIFF} // 60;

sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(folder_sync => sub { _sync($app, @_) });
}

sub _sync {
    my ($app, $job, $path, $recurs) = @_;
    return $job->fail('Empty path is not allowed') unless $path;
    return $job->fail('Trailing slash is forbidden') if '/' eq substr($path,-1) && $path ne '/';

    my $minion = $app->minion;
    return $job->finish('Previous folder sync job is still active')
        unless my $guard = $minion->guard('folder_sync' . $path, 360);

    my $schema = $app->schema;
    my $root   = $app->mc->root;
    $job->note($path => 1);

    my $realpath = $root->realpath($path, 1);
    $realpath = $path unless $realpath;
    if ($realpath ne $path) {
        $job->note(realpath => $realpath);
        $job->note($realpath => 1);

        $schema->resultset('Folder')->add_redirect($path, $realpath);
    }
    my $proj = $schema->resultset('Rollout')->project_for_folder($path);
    my ($proj_type, $proj_prefix);
    if ($proj) {
       $proj_type = $proj->{type};
       $proj_prefix = $proj->{prefix};
    }
    $job->note(proj_id => $proj->{project_id}, proj_name=> $proj->{name}, proj_prev_epc => $proj->{prev_epc}, proj_type => $proj_type, proj_prefix => $proj_prefix) if $proj_type;
    my $obsrelease = Directory::Scanner::OBSReleaseInfo->new($proj_type, $proj->{prev_epc}) if $proj_type;

    my $folder = $schema->resultset('Folder')->find({path => $realpath});
    unless ($root->is_dir($realpath)) {
        return $job->finish("not found") unless $folder;
        # Collect outcomes from recent jobs
        my %outcomes;
        my $jobs = $minion->jobs({tasks => ['folder_sync'], notes => [$realpath]});
        while (my $info = $jobs->next) {
            $outcomes{$info->{finished}} = $info->{result} if $info->{finished};
        }
        # at least one job older than MIRRORCACHE_FOLDER_DELETE_GRACE_TIMEOUT must complete
        # with result "$path is not a dir anymore"
        # all other jobs since that job must have the same outcome
        my $grace_start = 0;
        my $grace = $ENV{MIRRORCACHE_FOLDER_DELETE_JOB_GRACE_TIMEOUT} // 2*60*60;
        for my $tm (sort keys %outcomes) {
            my $outcome = $outcomes{$tm};
            if ($outcome && $outcome eq "$path is not a dir anymore") {
                $grace_start = $tm if($job->info->{started} - $tm > $grace);
            } else {
                $grace_start = 0;
            }
        }
        # means the conditions were met
        if ($grace_start) {
            $schema->resultset('Folder')->delete_cascade($folder->id, 0);
            return $job->finish("folder has been successfully deleted from DB");
        }
        $folder->update({sync_last => \'CURRENT_TIMESTAMP(3)', sync_requested => \'coalesce(sync_requested, CURRENT_TIMESTAMP(3))', sync_scheduled => \'coalesce(sync_scheduled, CURRENT_TIMESTAMP(3))'}); # prevent further sync attempts
        return $job->finish("$path is not a dir anymore");
    }

    # Mark sync_last early to stop other jobs to try to reschedule the sync
    my $otherFolder;
    my $update_db_last = sub {
        $folder->update({sync_last => \'CURRENT_TIMESTAMP(3)', sync_requested => \'coalesce(sync_requested, CURRENT_TIMESTAMP(3))', sync_scheduled => \'coalesce(sync_scheduled, CURRENT_TIMESTAMP(3))'});
        if ($realpath ne $path) {
            $otherFolder = $schema->resultset('Folder')->find({path => $path});
            $otherFolder->update({sync_last => \'CURRENT_TIMESTAMP(3)', sync_requested => \'coalesce(sync_requested, CURRENT_TIMESTAMP(3))', sync_scheduled => \'coalesce(sync_scheduled, CURRENT_TIMESTAMP(3))'}) if $otherFolder;
        }
    };

    my @subfolders;

    if ($folder) {
        $update_db_last->();
    } else {
        my $count = 0;
        my $has_pkg = 0;
        my $sub = sub {
            my ($file, $size, $mmode, $mtime, $target) = @_;
            my $subfolder;
            if ($root->is_remote) {
                $subfolder = 1 if $mmode && $mmode < 1000;
            } else {
                if ($path eq '/') {
                    $subfolder = 1 if $root->is_dir("$path$file");
                } else {
                    $subfolder = 1 if $root->is_dir("$path/$file");
                }
            }
            push @subfolders, $file if $subfolder && $recurs;
            $file = $file . '/' if $subfolder;
            $count = $count+1;
            $schema->resultset('File')->create({folder_id => $folder->id, name => $file, size => $size, mtime => $mtime, target => $target});
            $obsrelease->next_file($file, $mtime) if $obsrelease;
            if ( 0 == $has_pkg && $file =~ /\.(d?rpm|deb)$/ ) {
                $has_pkg = 1;
            }
            return undef;
        };
        eval {
            $folder = $schema->resultset('Folder')->find_or_create({path => $realpath});
            1;
        } or do {
            # folder often is concurently created fron FolderSyncScheduleFromMisses
            $folder = $schema->resultset('Folder')->find_or_create({path => $realpath}) unless $folder;
        };
        $update_db_last->();
        eval {
            $schema->txn_do(sub {
                $root->foreach_filename($realpath, $sub);
            });
            1;
        } or return $job->fail('Error while reading files from root :' . $@);

        $job->note(created => $realpath, count => $count);

        if ($count) {
            $schema->resultset('Folder')->request_scan($folder->id);
            $minion->enqueue('folder_hashes_create' => [$realpath] => {queue => $HASHES_QUEUE}) if $HASHES_COLLECT && !$app->backstage->inactive_jobs_exceed_limit(1000, 'folder_hashes_create', $HASHES_QUEUE);
            $minion->enqueue('folder_hashes_import' => [$realpath] => {queue => $HASHES_QUEUE}) if $HASHES_IMPORT && !$app->backstage->inactive_jobs_exceed_limit(1000, 'folder_hashes_import', $HASHES_QUEUE);
            $minion->enqueue('folder_pkg_sync' => [$realpath] => { queue => $job->info->{queue} }) if $has_pkg && !$app->backstage->inactive_jobs_exceed_limit(1000, 'folder_pkg_sync');
        }
        $schema->resultset('Folder')->request_scan($otherFolder->id) if $otherFolder && ($count || !$otherFolder->scan_requested);
        $schema->resultset('Rollout')->add_rollout($proj->{project_id}, $obsrelease->versionmtime, $obsrelease->version, $obsrelease->versionfilename, $proj_prefix) if $obsrelease && $obsrelease->versionfilename;

        for my $subfolder (@subfolders) {
            $app->backstage->enqueue('folder_sync', "$path/$subfolder");
        }
        return;
    };
    return $job->fail("Couldn't create folder $path in DB") unless $folder && $folder->id;

    my $folder_id = $folder->id;
    my %dbfileids = ();
    my %dbfilesizes = ();
    my %dbfilemtimes = ();
    my %dbfiletargets = ();
    for my $file ($schema->resultset('File')->search({folder_id => $folder_id})) {
        my $basename = $file->name;
        next unless $basename;
        $dbfileids{$basename} = $file->id;
        $dbfilesizes{$basename} = $file->size if defined $file->size;
        $dbfilemtimes{$basename} = $file->mtime if defined $file->mtime;
        $dbfiletargets{$basename} = $file->target if defined $file->target;
    }
    my %dbfileidstodelete = %dbfileids;

    my $cnt = 0, my $updated = 0;
    my $has_pkg = 0;
    my $sub = sub {
        my ($file, $size, $mmode, $mtime, $target) = @_;
        my $subfolder;
        if ($root->is_remote) {
            $subfolder = 1 if $mmode && $mmode < 1000;
        } else {
            if ($path eq '/') {
                $subfolder = 1 if $root->is_dir("$path$file");
            } else {
                $subfolder = 1 if $root->is_dir("$path/$file");
            }
        }
        push @subfolders, $file if $subfolder && $recurs;
        $file = $file . '/' if $subfolder;
        if ($dbfileids{$file}) {
            my $id = delete $dbfileidstodelete{$file};
            if (
                (defined $size && defined $mtime)
                &&
                (
                    $size != ($dbfilesizes{$file} // -1)
                    ||
                    $SCAN_MTIME_DIFF < abs($mtime - ($dbfilemtimes{$file} // -1)) # when scanning over http the seconds mightbe truncated from mtime - we must tolerate it here
                )                                                   # otherwise folder_diff_server.dt will be no longer valid if we increase dt
                ||
                (defined $target && $target ne ($dbfiletargets{$file} // ''))
            ) {
                $schema->storage->dbh->prepare(
                    "UPDATE file set size = ?, mtime = ?, target = ?, dt = CURRENT_TIMESTAMP(3) where id = ?"
                )->execute($size, $mtime, $target, $id);
                $updated = $updated + 1;
            }
            return;
        }
        $obsrelease->next_file($file, $mtime) if $obsrelease;
        if ( 0 == $has_pkg && $file =~ /\.(d?rpm|deb)$/ ) {
            $has_pkg = 1;
        }
        $cnt = $cnt + 1;
        $schema->resultset('File')->create({folder_id => $folder->id, name => $file, size => $size, mtime => $mtime, target => $target});
        return undef;
    };
    $root->foreach_filename($realpath, $sub)  or
            return $job->fail('Error while reading files from root');
    my @idstodelete = values %dbfileidstodelete;
    $schema->storage->dbh->do(
      sprintf(
        'DELETE FROM file WHERE id IN(%s)',
        join ',', ('?') x @idstodelete
      ),
      {},
      @idstodelete,
    ) if @idstodelete;
    my $deleted = @idstodelete;

    $job->note(updated => $realpath, count => $cnt, deleted => $deleted, updated => $updated);
    if ($cnt || $updated) {
        $folder->update( {sync_last => \"CURRENT_TIMESTAMP(3)", scan_requested => \"CURRENT_TIMESTAMP(3)", sync_scheduled => \'coalesce(sync_scheduled, CURRENT_TIMESTAMP(3))'});
    } else {
        $folder->update( {sync_last => \"CURRENT_TIMESTAMP(3)", sync_scheduled => \'coalesce(sync_scheduled, CURRENT_TIMESTAMP(3))'});
    }
    my $need_hashes = $cnt || $updated ? 1 : 0;
    my $max_dt;
    if ( ($HASHES_COLLECT || $HASHES_IMPORT) ) {
        if(my $res = $schema->resultset('File')->need_hashes($folder_id)) {
            $need_hashes = $res->{file_id} unless $need_hashes;
            $max_dt      = $res->{max_dt};
        }
    }
    if ($need_hashes) {
        $minion->enqueue('folder_hashes_create' => [$realpath, $max_dt] => {queue => $HASHES_QUEUE}) if $HASHES_COLLECT && !$app->backstage->inactive_jobs_exceed_limit(1000, 'folder_hashes_create', $HASHES_QUEUE);
        $minion->enqueue('folder_hashes_import' => [$realpath, $max_dt] => {queue => $HASHES_QUEUE}) if $HASHES_IMPORT && !$app->backstage->inactive_jobs_exceed_limit(1000, 'folder_hashes_import', $HASHES_QUEUE);
    }
    $minion->enqueue('folder_pkg_sync' => [$realpath] => { queue => $job->info->{queue} }) if $has_pkg && !$app->backstage->inactive_jobs_exceed_limit(1000, 'folder_pkg_sync', $job->info->{queue});

    if ($otherFolder && ($cnt || $updated || !$otherFolder->scan_requested)) {
        $otherFolder->update({sync_last => \"CURRENT_TIMESTAMP(3)", scan_requested => \"CURRENT_TIMESTAMP(3)", sync_scheduled => \'coalesce(sync_scheduled, CURRENT_TIMESTAMP(3))'});
    } else {
        $otherFolder->update({sync_last => \"CURRENT_TIMESTAMP(3)", sync_scheduled => \'coalesce(sync_scheduled, CURRENT_TIMESTAMP(3))'}) if $otherFolder;
    }
    $schema->resultset('Rollout')->add_rollout($proj->{project_id}, $obsrelease->versionmtime, $obsrelease->version, $obsrelease->versionfilename, $proj_prefix) if $obsrelease && $obsrelease->versionfilename;


    for my $subfolder (@subfolders) {
        $app->backstage->enqueue('folder_sync', "$path/$subfolder");
    }
}

1;
