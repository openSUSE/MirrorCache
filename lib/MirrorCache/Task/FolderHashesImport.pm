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

package MirrorCache::Task::FolderHashesImport;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::UserAgent;

sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(folder_hashes_import => sub { _run($app, @_) });
}

sub _run {
    my ($app, $job, $path) = @_;
    return $job->fail('Empty path is not allowed') unless $path;
    return $job->fail('Trailing slash is not allowed') if '/' eq substr($path, -1) && $path ne '/';
    return $job->fail('MIRRORCACHE_HEADQUARTER is not set') unless $ENV{MIRRORCACHE_HEADQUARTER};

    my $minion = $app->minion;
    return $job->finish('Previous folder hashes import job is still active')
      unless my $guard = $minion->guard('folder_hashes_import' . $path, 360);

    my $schema = $app->schema;
    my $root   = $app->mc->root;
    $job->note($path => 1);

    my $folder = $schema->resultset('Folder')->find({path => $path});
    return $job->finish("not found") unless $folder;

    my $folder_id = $folder->id;
    my $count     = 0;
    my $errcount  = 0;

    my $max_dt = $folder->hash_last_import;
    $max_dt = $max_dt ? "&since=$max_dt" : '';
    $job->note(max_dt => $max_dt);

    my $hq_url = $ENV{MIRRORCACHE_HEADQUARTER} . $path . '?hashes' . $max_dt;
    $hq_url = "http://" . $hq_url unless 'http' eq substr($hq_url, 0, 4);

    my $mojo_url = Mojo::URL->new($hq_url);
    my $res      = Mojo::UserAgent->new->get($mojo_url, {'User-Agent' => 'MirrorCache/hashes_import'})->result;
    return $job->fail('Request to HEADQUARTER ' . $hq_url . ' failed, response code ' . $res->code)
      if $res->code != 200;

    my $res_json = $res->json;
    my $last_import;
    for my $hash (@$res_json) {
        my $basename = $hash->{name};
        next unless $basename;
        my $file = $schema->resultset('File')->find({folder_id => $folder_id, name => $basename});
        next unless $file;
        eval {
            $schema->resultset('Hash')->store($file->id, $hash->{mtime}, $hash->{size}, $hash->{md5},
                $hash->{sha1}, $hash->{sha256}, $hash->{piece_size}, $hash->{pieces}, undef, undef, undef, $hash->{target});
            $last_import = Mojo::Date($hash->{dt}) if ($last_import && $hash->{dt} && $last_import->epoch < Mojo::Date->new($hash->{dt})->epoch);
            $count++;
        };
        if ($@) {
            my $err = $@;
            $app->log->warn("Error while storing hash data for file $path/$basename:");
            $app->log->warn($err);
            $errcount++;
        }
    }

    $folder->hash_last_import($last_import) if $last_import && $count;
    $job->note(count => $count, errors => $errcount);
}

1;
