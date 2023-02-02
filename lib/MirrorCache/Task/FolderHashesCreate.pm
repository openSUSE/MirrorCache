# Copyright (C) 2021 SUSE LLC
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

package MirrorCache::Task::FolderHashesCreate;
use Mojo::Base 'Mojolicious::Plugin';
use XML::Writer;
use IO::File;
use Digest::SHA;
use Digest::MD5;
use File::Path 'make_path';
use File::stat;

my $HASHES_PIECES_MIN_SIZE = $ENV{MIRRORCACHE_HASHES_PIECES_MIN_SIZE}// 2*256*1024;

sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(folder_hashes_create => sub { _sync($app, @_) });
}

sub _sync {
    my ($app, $job, $path, $dt) = @_;
    return $job->fail('Empty path is not allowed') unless $path;
    return $job->fail('Trailing slash is not allowed') if '/' eq substr($path,-1) && $path ne '/';

    my $minion = $app->minion;
    return $job->finish('Previous folder hashes create job is still active')
        unless my $guard = $minion->guard('folder_hashes_create' . $path, 360);

    my $schema = $app->schema;
    my $root   = $app->mc->root;
    return $job->fail('Job can be run only with local files available') if $root->is_remote;
    $job->note($path => 1);

    my $folder = $schema->resultset('Folder')->find({path => $path});
    return $job->finish("not found") unless $folder;

    my $folder_id = $folder->id;
    my $count = 0;
    my $errcount = 0;
    my $rows = $schema->resultset('File')->hash_needed($folder_id, $dt);
    for my $id (sort keys %$rows) {
        my $file = $rows->{$id};
        my $basename = $file->{name};
        next unless $basename;
        my $block_size = calcBlockSize($file->{size});
        eval {
            my $indir = $root->rootpath($path);
            calcMetalink($indir, $path, $basename, $block_size, $schema, $file->{id});
            $count++;
        };
        if ($@) {
            my $err = $@;
            $app->log->warn("Error while calculating metalink for file $path/$basename:");
            $app->log->warn($err);
            $errcount++;
        }
    }

    $job->note(count => $count, errors => $errcount);
}

sub calcBlockSize {
    my $fileSize = shift;
    return 0 if !$fileSize || $fileSize <= $HASHES_PIECES_MIN_SIZE; # don't create piece hashes
    return 256*1024 if $fileSize < 8*1024*1024;
    return 1024*1024 if $fileSize < 256*1024*1024;
    return 4*1024*1024;
}

sub calcMetalink {
    my ($indir, $path, $file, $block_size, $schema, $file_id) = @_;
    my $f = "$indir$path/$file";

    my $target;
    eval {
        my $dest = readlink($f);
        if ($dest) {
            $dest = Mojo::File->new($dest);
            $target = $dest->basename if $dest->dirname eq '.' || $dest->dirname eq "$indir$path";
        }
    };
    return $schema->resultset('Hash')->store($file_id, undef, 0, undef, undef, undef, undef, undef, undef, undef, undef, undef, $target) if $target;

    open my $fh, "<", $f or die "Unable to open $f!";
    my $stat = stat($fh);
    my $mtime = $stat->mtime;
    my $d1   = Digest::SHA->new(1);
    my $d256 = Digest::SHA->new(256);
    my $d512 = Digest::SHA->new(512);
    my $dmd5 = Digest::MD5->new;
    my @pieces;
    my $data;
    my $size = $stat->size;
    my $buffer_length = $block_size; # $block_size may be 0, means no pieces are needed
    $buffer_length = 1024*1024 unless $buffer_length;

    my $zsync;
    eval {
        require Digest::Zsync;
        $zsync = Digest::Zsync->new->init($size);
    } if $ENV{MIRRORCACHE_ZSYNC_COLLECT} && $file =~ m/\.$ENV{MIRRORCACHE_ZSYNC_COLLECT}$/;

    while (read $fh, $data, $buffer_length) {
        push @pieces, Digest::SHA::sha1_hex($data) if $block_size;
        $zsync->add($data) if $zsync;

        $d1->add($data);
        $d256->add($data);
        $d512->add($data);
        $dmd5->add($data);
    }
    close $fh;
    my $pieceshex = join '', @pieces;
    my ($zsync_lengths, $zsync_block_size, $zsync_hashes);
    if ($zsync) {
        $zsync_lengths    = $zsync->lengths;
        $zsync_block_size = $zsync->block_size;
        $zsync_hashes     = $zsync->digest;
    }
    $schema->resultset('Hash')->store($file_id, $mtime, $size, $dmd5->hexdigest, $d1->hexdigest, $d256->hexdigest, $d512->hexdigest, $block_size, $pieceshex, $zsync_lengths, $zsync_block_size, $zsync_hashes);
}

1;
