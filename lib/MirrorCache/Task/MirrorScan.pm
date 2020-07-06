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

sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(mirror_scan => sub { _scan($app, @_) });
}

sub _scan {
    my ($app, $job, $path) = @_;

    my $schema = $app->schema;
    my $minion = $app->minion;

    my $folder = $schema->resultset('Folder')->find({path => $path});
    unless ($folder) {
        my $guard = $app->minion->guard('create_folder' . $path, 60);
        $folder = $schema->resultset('Folder')->find_or_create({path => $path});
        # hack - must scan "$root$folder" insted
        if ($path eq '/folder1') {
            $schema->resultset('File')->find_or_create({folder_id => $folder->id, name => 'file1.dat'});
        }
    };
    return undef unless $folder && $folder->id;

    my $folder_on_mirrors = $schema->resultset('Server')->folder($folder->id);
    my $ua  = Mojo::UserAgent->new;
    # my $i=0;
    my $folder_id = $folder->id;
    for my $folder_on_mirror (@$folder_on_mirrors) {
        my $url = $folder_on_mirror->{url};
        my $promise = $ua->get_p($url)->then(sub {
            # $i = $i+1;
            # $job->note($i => $url, "x$i" => $folder_on_mirror->{server_id}, "f$i" => $folder_id, xx => 1, yy => $folder_id);
            my $tx = shift;
            # return $schema->resultset('Server')->forget_folder($folder_on_mirror->{server_id}, $folder_on_mirror->{folder_diff_id}) if $tx->result->code == 404;
            # return undef if $tx->result->code == 404;

            return $app->emit_event('mc_mirror_probe_error', {mirror => $folder_on_mirror->{server_id}, err => $tx->result->code}, $folder_on_mirror->{server_id}) if $tx->result->code > 299;

            my $dom = $tx->result->dom;
            my $ctx = Digest::MD5->new;
            for my $i (sort { $a->attr->{href} cmp $b->attr->{href} } $dom->find('a')->each) {
                my $href = $i->attr->{href};
                my $text = $i->text;
                $ctx->add($href) if $text eq $href; # TODO skip files if they are not on the main server
            }
            my $digest = $ctx->hexdigest;
            my $folder_diff = $schema->resultset('FolderDiff')->find({folder_id => $folder_id, hash => $digest});
            unless ($folder_diff) {
                my $guard = $app->minion->guard("create_folder_diff_${folder_id}_$digest" , 60);
                $folder_diff = $schema->resultset('FolderDiff')->find_or_new({folder_id => $folder_id, hash => $digest});
                unless($folder_diff->in_storage) {
                    $folder_diff->insert;
                    # TODO add missing files to folder_diff_file
                }
            }
            # do nothing in diff_id is the same
            return undef if $folder_on_mirror->{folder_diff_id} && $folder_diff->id eq $folder_on_mirror->{folder_diff_id};

            # $schema->resultset('FolderDiffServer')->update_or_create_by_folder_id({folder_diff_id => $folder_diff->{id}, server_id => $folder_on_mirror->{server_id}});
            my $fds = $schema->resultset('FolderDiffServer')->new({folder_diff_id => $folder_diff->id, server_id => $folder_on_mirror->{server_id}});
            $fds->insert;

        })->catch(sub {
            my $err = shift;
            return $app->emit_event('mc_mirror_probe_error', {mirror => $folder_on_mirror->{server_id}, err => $err}, $folder_on_mirror->{server_id});
        })->wait;
    }
    
    ;
}

1;
