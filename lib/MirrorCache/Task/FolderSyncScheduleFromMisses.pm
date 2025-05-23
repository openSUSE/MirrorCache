# Copyright (C) 2020,2021 SUSE LLC
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

package MirrorCache::Task::FolderSyncScheduleFromMisses;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::File qw(path);

sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(folder_sync_schedule_from_misses => sub { _run($app, @_) });
    $app->minion->add_task(folder_sync_schedule_from_misses_shard => sub { _run_shard($app, @_) });
}

my $DELAY = int($ENV{MIRRORCACHE_SCHEDULE_RETRY_INTERVAL} // 10);
my $MCDEBUG = $ENV{MCDEBUG_TASK_FOLDER_SYNC_SCHEDULE_FROM_MISSES} // $ENV{MCDEBUG_ALL} // 0;

sub _run {
    my ($app, $job, $prev_stat_id) = @_;
    my $job_id = $job->id;
    my $pref = "[schedule_from_misses $job_id]";
    my $id_in_notes = $job->info->{notes}{stat_id};
    $prev_stat_id = $id_in_notes if $id_in_notes;
    print(STDERR "$pref read id from notes: $id_in_notes\n") if $MCDEBUG && $id_in_notes;
    print(STDERR "$pref use id from param: $prev_stat_id\n") if $MCDEBUG && $prev_stat_id && (!$id_in_notes || $prev_stat_id != $id_in_notes);

    my $minion = $app->minion;
    # prevent multiple scheduling tasks to run in parallel
    return $job->finish('Previous schedule_from_misses job is still active')
      unless my $guard = $minion->guard('folder_sync_schedule_from_misses', 180);

    # Cannot lock schedule_from_misses lock
    return $job->retry({delay => 10})
      unless my $common_guard = $minion->guard('schedule_from_misses', 60);

    my $schema = $app->schema;
    my $limit = 10000;

    $prev_stat_id = $schema->resultset('Stat')->secure_max_id($prev_stat_id);
    print(STDERR "$pref id after adjust: $prev_stat_id\n") if $MCDEBUG;

    my ($stat_id, $folders, $country_list) = $schema->resultset('Stat')->path_misses($prev_stat_id, $limit);
    $common_guard = undef;
    my $rs = $schema->resultset('Folder');
    my $last_run = 0;
    print STDERR $app->dumper($pref, $folders, $stat_id, $prev_stat_id) if $MCDEBUG;

    # we will schedule folder_sync_schedule_from_misses_shard for each affected shard with range ($prev_stat_id, $next_stat_id)
    my %affected_shards;

    while (scalar(@$folders)) {
        my $cnt = 0;
        print(STDERR "$pref read id from stat up to: $stat_id\n");
        for my $path (@$folders) {
            print STDERR $pref . $path . "\n" if $MCDEBUG;
            my $folder = $rs->find({ path => $path });
            if (!$folder) {
                my $shard  = $app->mcproject->shard_for_path($path);
                if ($shard) {
                    $affected_shards{$shard} = 1;
                } elsif (!$app->mc->root->is_dir($path)) {
                    $path = Mojo::File->new($path)->dirname;
                    next unless $app->mc->root->is_dir($path);
                }
            }
            $folder = $rs->find({ path => $path }) unless $folder;

            $cnt = $cnt + 1;
            print STDERR $pref . $path . "\n\n" if $MCDEBUG;
            $rs->request_sync($path);
            if ($folder && $folder->id) {
                $rs->request_scan($folder->id);
            }
        }
        @$country_list = ('') if $cnt && !@$country_list;
        for my $country (@$country_list) {
            next unless $minion->lock('mirror_probe_scheduled_' . $country, 60); # don't schedule if schedule happened in last 60 sec
            next unless $minion->lock('mirror_probe_incomplete_for_' . $country, 600); # don't schedule until probe job completed
            $minion->unlock('mirror_force_done');
            $minion->enqueue('mirror_probe' => [$country] => {priority => 6});
        }
        $last_run = $last_run + $cnt;
        last unless $cnt;
        $limit = 10000;
        ($stat_id, $folders, $country_list) = $schema->resultset('Stat')->path_misses($stat_id, $limit);
    }

    if ($minion->lock('mirror_force_done', 9000)) {
        if ($minion->lock('schedule_mirror_force_ups', 9000)) {
            $minion->enqueue('mirror_force_ups' => [] => {priority => 10});
        }

        if ($minion->lock('schedule_mirror_force_downs', 300)) {
            $minion->enqueue('mirror_force_downs' => [] => {priority => 10});
        }
    }

    $prev_stat_id = 0 unless $prev_stat_id;
    print(STDERR "$pref will retry with id: $prev_stat_id\n") if $MCDEBUG;
    my $total = $job->info->{notes}{total};
    $total = 0 unless $total;
    $total += $last_run if $last_run;
    $job->note(stat_id => $stat_id, total => $total, last_run => $last_run);

    for my $shard (keys %affected_shards) {
        $minion->enqueue('folder_sync_schedule_from_misses_shard' => [$prev_stat_id, $stat_id, $shard] => {queue => $shard});
    }

    return $job->finish unless $DELAY;
    return $job->retry({delay => $DELAY});
}


# files from shards are available only special workeds, thus a dedicated job to run in a queue of those workers
sub _run_shard {
    my ($app, $job, $min_stat_id, $max_stat_id, $shard) = @_;
    my $job_id = $job->id;
    my $pref = "[schedule_from_misses$shard $job_id]";

    return $job->finish("something is missing: $min_stat_id, $max_stat_id, $shard")
        unless defined $min_stat_id && $max_stat_id && $shard;

    my $minion = $app->minion;
    # prevent multiple scheduling tasks to run in parallel
    return $job->finish("Previous schedule_from_misses_$shard job is still active")
        unless my $guard = $minion->guard("folder_sync_schedule_from_misses_$shard", 180);

    my $schema = $app->schema;

    my $folders = $schema->resultset('Stat')->path_misses_shard($min_stat_id, $max_stat_id, $shard);
    my $rs = $schema->resultset('Folder');

    while (scalar(@$folders)) {
        my $cnt = 0;
        for my $path (@$folders) {
            my $folder = $rs->find({ path => $path });
            if (!$folder) {
                if (!$app->mc->root->is_dir($path)) {
                    $path = Mojo::File->new($path)->dirname;
                    next unless $app->mc->root->is_dir($path);
                }
            }
            $folder = $rs->find({ path => $path }) unless $folder;

            $cnt = $cnt + 1;
            $rs->request_sync($path);
            if ($folder && $folder->id) {
                $rs->request_scan($folder->id);
            }
        }
    }

    return $job->finish("Done $shard for range $min_stat_id, $max_stat_id");
}

1;
