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

package MirrorCache::Task::MirrorScan;
use Mojo::Base 'Mojolicious::Plugin';

use DateTime;
use Digest::MD5;
use Mojo::UserAgent;
use Mojo::Util ('trim');
use URI;
use URI::Encode ('uri_decode');
use File::Basename;

sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(mirror_scan => sub { _scan($app, @_) });
}

# many html pages truncate file names
# use last 42 characters to compare for now
sub _reliable_prefix {
    substr(shift, 0, 42);
}

sub _scan {
    my ($app, $job, $path, $country) = @_;
    return $job->fail('Empty path is not allowed') unless $path;
    return $job->fail('Trailing slash is forbidden') if '/' eq substr($path,-1) && $path ne '/';
    $country = "" unless $country;

    my $minion = $app->minion;
    return $job->finish('Previous mirror scan job is still active')
        unless my $guard = $minion->guard('mirror_scan' . $path, 360);

    $job->note($path => 1);
    my $schema = $app->schema;
    my $folder = $schema->resultset('Folder')->find({path => $path});
    return undef unless $folder && $folder->id; # folder is not added to db yet
    # we collect max(dt) here to avoid race with new files added to DB
    my $latestdt = $schema->resultset('File')->find({folder_id => $folder->id}, {
        columns => [ { max_dt => { max => "dt" } }, ]
    })->get_column('max_dt');

    unless ($latestdt) {
        return $job->note(skip_reason => 'latestdt empty', folder_id => $folder->id);
    }
    my $folder_id = $folder->id;
    my @dbfiles = ();
    my %dbfileids = ();
    my %dbfileprefixes = ();
    for my $file ($schema->resultset('File')->search({folder_id => $folder_id})) {
        my $basename = $file->name;
        next unless $basename; # && -f $localdir . $basename; # skip deleted files
        $dbfileprefixes{_reliable_prefix($basename)} = 1;
        push @dbfiles, $basename;
        $dbfileids{$basename} = $file->id;
    }

    my $folder_on_mirrors = $schema->resultset('Server')->folder($folder->id, $country);
    my $ua = Mojo::UserAgent->new;
    for my $folder_on_mirror (@$folder_on_mirrors) {
        my $server_id = $folder_on_mirror->{server_id};
        my $url = $folder_on_mirror->{url} . '/';
        my $promise = $ua->get_p($url)->then(sub {
            my $tx = shift;
            # return $schema->resultset('Server')->forget_folder($folder_on_mirror->{server_id}, $folder_on_mirror->{folder_diff_id}) if $tx->result->code == 404;
            # return undef if $tx->result->code == 404;

            return $app->emit_event('mc_mirror_probe_error', {mirror => $folder_on_mirror->{server_id}, url => "u$url", err => $tx->result->code}, $folder_on_mirror->{server_id}) if $tx->result->code > 299;

            my $dom = $tx->result->dom;
            my $ctx = Digest::MD5->new;
            my %mirrorfiles = ();

            for my $i (sort { $a->attr->{href} cmp $b->attr->{href} } $dom->find('a')->each) {
                my $text = trim $i->text;
                my $href = basename($i->attr->{href});
                $href = uri_decode(URI->new($href));
                # we can do _reliable_prefix() only after uri_decode
                my $href1 = _reliable_prefix($href);
                my $text1 = _reliable_prefix($text);
                if ($href1 eq $text1 && $dbfileprefixes{$text1}) {
                    $ctx->add($href);
                    $mirrorfiles{$href} = 1;
                }
            }
            my $digest = $ctx->hexdigest;
            my $folder_diff = $schema->resultset('FolderDiff')->find({folder_id => $folder_id, hash => $digest});
            unless ($folder_diff) {
                $folder_diff = $schema->resultset('FolderDiff')->find_or_new({folder_id => $folder_id, hash => $digest});
                unless($folder_diff->in_storage) {
                    $folder_diff->dt($latestdt);
                    $folder_diff->insert;
                    
                    foreach my $file (@dbfiles) {
                        next if $mirrorfiles{$file};
                        my $id = $dbfileids{$file};
                        $schema->resultset('FolderDiffFile')->create({folder_diff_id => $folder_diff->id, file_id => $id}) if $id;
                    }
                }
            }
            $job->note("hash$server_id" => $digest);
            my $old_diff_id = $folder_on_mirror->{diff_id} || 0;
            # do nothing if diff_id is the same
            return undef if $folder_diff->id == $old_diff_id;

            if ($old_diff_id) {
                # we need update existing entry
                $schema->resultset('FolderDiffServer')->update_diff_id($folder_diff->id, $folder_on_mirror->{server_id}, $old_diff_id);
            } else {
                # need new entry
                $schema->resultset('FolderDiffServer')->create( {server_id => $folder_on_mirror->{server_id}, folder_diff_id => $folder_diff->id } );
            }
        })->catch(sub {
            my $err = shift;
            return $app->emit_event('mc_mirror_probe_error', {mirror => $folder_on_mirror->{server_id}, url => "u$url", err => $err}, $folder_on_mirror->{server_id});
        })->timeout(120)->wait;
    }
    
    $app->emit_event('mc_mirror_scan_complete', {path => $path, tag => $folder->id, country => $country});
}

1;
