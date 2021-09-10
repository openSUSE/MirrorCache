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
use URI::Escape ('uri_unescape');
use File::Basename;
use Encode qw(decode);
use HTML::Parser;

use MirrorCache::Utils 'region_for_country';

sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(mirror_scan => sub { _scan($app, @_) });
}

# many html pages truncate file names
# use last 42 characters to compare for now
sub _reliable_prefix {
    substr(shift, 0, 20);
}

sub _scan {
    # region is considered only if country is empty
    my ($app, $job, $path, $country, $region) = @_;
    return $job->fail('Empty path is not allowed') unless $path;
    return $job->fail('Trailing slash is forbidden') if '/' eq substr($path,-1) && $path ne '/';
    $country = "" unless $country;
    $country =~ s/^\s+|\s+$//g;
    $region  = "" unless $region;

    my $minion = $app->minion;
    return $job->finish('Previous mirror scan job is still active')
        unless my $guard = $minion->guard('mirror_scan' . $path . '_' .  $country, 360);

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
    my $max_dt = 0;
    for my $file ($schema->resultset('File')->search({folder_id => $folder_id})) {
        my $basename = $file->name;
        next unless $basename;
        next if substr($basename, length($basename)-1) eq '/'; # skip folders
        $dbfileprefixes{_reliable_prefix($basename)} = 1;
        push @dbfiles, $basename;
        $dbfileids{$basename} = $file->id;
        $max_dt = $file->dt if !$max_dt || ( 0 > DateTime->compare($max_dt, $file->dt) );
    }
    @dbfiles = sort @dbfiles;

    my $folder_on_mirrors = $schema->resultset('Server')->folder($folder->id, $country, $region);
    my $count = 0;
    for my $folder_on_mirror (@$folder_on_mirrors) {
        my $server_id = $folder_on_mirror->{server_id};
        my $url = $folder_on_mirror->{url} . '/';
        # it looks that  defining $ua outside the loop greatly increases overal memory usage footprint for the task
        my $ua = Mojo::UserAgent->new->max_redirects(10);
        $job->note("hash$server_id" => undef);
        my $promise = $ua->get_p($url)->then(sub {
            $count++;
            my $tx = shift;
            my $sid = $folder_on_mirror->{server_id};
            # return $schema->resultset('Server')->forget_folder($folder_on_mirror->{server_id}, $folder_on_mirror->{folder_diff_id}) if $tx->result->code == 404;
            # return undef if $tx->result->code == 404;
            return $app->emit_event('mc_mirror_probe_error', {mirror => $sid, url => "u$url", err => $tx->result->code}, $folder_on_mirror->{server_id}) if $tx->result->code > 299;
            # we cannot mojo dom here because it takes too much RAM for huge html page
            # my $dom = $tx->result->dom;
            my %mirrorfiles = ();
            my $href = '';
            my $href1 = '';
            my $start = sub {
                return undef unless $_[0] eq 'a';
                $href = $_[1]->{href};
                $href1 = '';
                eval {
                    if ('/' eq substr($href, -1)) {
                        $href = basename($href) . '/';
                    } else {
                        $href = basename($href);
                    }
                    $href = uri_unescape($href);
                    1;
                } or $href = '';
            };
            my $end = sub {
                $href = '';
                $href1 = '';
            };
            my $text = sub {
                my $t = shift;
                $t = trim $t if $t;
                return unless ($t && $href);
                $href1 = _reliable_prefix($href) unless $href1;
                my $t1;
                if ('/' eq substr($t, -1)) {
                    $t1 =  basename(_reliable_prefix($t)) . '/';
                }  else {
                    $t1 =  basename(_reliable_prefix($t));
                }

                $mirrorfiles{$href} = 1 if ($href1 eq $t1 && $dbfileprefixes{$t1});
            };
            my $p = HTML::Parser->new(
                api_version => 3,
                start_h => [$start, "tagname, attr"],
                text_h  => [$text,  "dtext" ],
                end_h   => [$end,   "tagname"],
            );

            my $offset = 0;
            while (1) {
                my $chunk = $tx->result->get_body_chunk($offset);
                if (!defined($chunk)) {
                    $ua->loop->one_tick unless $ua->loop->is_running;
                    next;
                }
                my $l = length $chunk;
                last unless $l > 0;
                # try to detect encoding
                if ($offset == 0) {
                    eval {
                        $p->utf8_mode(1) if index(encode_utf8($chunk),'charset=utf-8') > 0;
                    };
                }
                $offset += $l;
                $p->parse($chunk);
            }
            $p->eof;

            my $ctx = Digest::MD5->new;
            my @missing_files = ();
            foreach my $file (@dbfiles) {
                next if $mirrorfiles{$file} || substr($file,length($file)-1) eq '/';
                $ctx->add($file);
                push @missing_files, $dbfileids{$file};
            }
            my $digest = $ctx->hexdigest;
            my $folder_diff = $schema->resultset('FolderDiff')->find({folder_id => $folder_id, hash => $digest});
            unless ($folder_diff) {
                $folder_diff = $schema->resultset('FolderDiff')->find_or_new({folder_id => $folder_id, hash => $digest});
                unless($folder_diff->in_storage) {
                    $folder_diff->dt($latestdt);
                    $folder_diff->insert;

                    foreach my $id (@missing_files) {
                        $schema->resultset('FolderDiffFile')->create({folder_diff_id => $folder_diff->id, file_id => $id}) if $id;
                    }
                }
            }
            $job->note("hash$server_id" => $digest);
            my $old_diff_id = $folder_on_mirror->{diff_id} || 0;
            my $old_diff_dt_epoch = $folder_on_mirror->{dt_epoch} || 0;
            if ($folder_diff->id == $old_diff_id) {
                # need update dt if diff_id is the same
                $schema->resultset('FolderDiffServer')->update_dt($max_dt, $folder_diff->id, $folder_on_mirror->{server_id}) if $old_diff_dt_epoch < $max_dt->epoch;
                return;
            }

            if ($old_diff_id) {
                # we need update existing entry
                $schema->resultset('FolderDiffServer')->update_diff_id($folder_diff->id, $max_dt, $old_diff_id, $folder_on_mirror->{server_id});
            } else {
                # need new entry
                $schema->resultset('FolderDiffServer')->create( {server_id => $folder_on_mirror->{server_id}, folder_diff_id => $folder_diff->id, dt => $max_dt } );
            }
        })->catch(sub {
            my $err = shift;
            return $app->emit_event('mc_mirror_probe_error', {mirror => $folder_on_mirror->{server_id}, url => "u$url", err => $err}, $folder_on_mirror->{server_id});
        })->timeout(180)->wait;
    }

    $app->emit_event('mc_mirror_scan_complete', {path => $path, tag => $folder->id, country => $country, count => $count});
    # scan continent if no mirror in the country has the folder
    return undef if !$country || $region || $count;

    $region = region_for_country($country);
    if ($region) {
        $minion->enqueue('mirror_scan' => [$path, '', $region] => {priority => 6} );
    }
}

1;
