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
use MirrorCache::Utils 'datetime_now';

my $HASHES_COLLECT = $ENV{MIRRORCACHE_HASHES_COLLECT} // 0;
my $HASHES_IMPORT  = $ENV{MIRRORCACHE_HASHES_IMPORT} // 0;
my $HASHES_QUEUE   = $ENV{MIRRORCACHE_HASHES_QUEUE} // 'hashes';

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
    $job->note($path => 1);

    my $realpath = $root->realpath($path);
    $realpath = $path unless $realpath;
    if ($realpath ne $path) {
        $job->note(realpath => $realpath);
        $job->note($realpath => 1);
    }

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

    if ($folder) {
        $update_db_last->();
    } else {
        my $count = 0;
        my $sub = sub {
            my ($file, $size, $mmode, $mtime, $target) = @_;
            $file = $file . '/' if !$root->is_remote && $path ne '/' && $root->is_dir("$path/$file");
            $file = $file . '/' if !$root->is_remote && $path eq '/' && $root->is_dir("$path$file");
            $file = $file . '/' if $mmode && $root->is_remote && $mmode < 1000;
            $count = $count+1;
            $schema->resultset('File')->create({folder_id => $folder->id, name => $file, size => $size, mtime => $mtime, target => $target});
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
        }
        $schema->resultset('Folder')->request_scan($otherFolder->id) if $otherFolder && ($count || !$otherFolder->scan_requested);
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
    my $sub = sub {
        my ($file, $size, $mmode, $mtime, $target) = @_;
        $file = $file . '/' if !$root->is_remote && $path ne '/' && $root->is_dir("$path/$file");
        $file = $file . '/' if !$root->is_remote && $path eq '/' && $root->is_dir("$path$file");
        $file = $file . '/' if $mmode && $root->is_remote && $mmode < 1000;
        if ($dbfileids{$file}) {
            my $id = delete $dbfileidstodelete{$file};
            if (
                (defined $size && defined $mtime) && ($size != $dbfilesizes{$file} || $mtime != $dbfilemtimes{$file})
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

    if ($otherFolder && ($cnt || $updated || !$otherFolder->scan_requested)) {
        $otherFolder->update({sync_last => \"CURRENT_TIMESTAMP(3)", scan_requested => \"CURRENT_TIMESTAMP(3)", sync_scheduled => \'coalesce(sync_scheduled, CURRENT_TIMESTAMP(3))'});
    } else {
        $otherFolder->update({sync_last => \"CURRENT_TIMESTAMP(3)", sync_scheduled => \'coalesce(sync_scheduled, CURRENT_TIMESTAMP(3))'}) if $otherFolder;
    }
}

1;
