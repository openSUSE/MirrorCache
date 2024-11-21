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

package MirrorCache::Task::FolderPkgSync;
use Mojo::Base 'Mojolicious::Plugin';
use MirrorCache::Utils 'datetime_now';

use Directory::Scanner::OBSMediaVersion;

sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(folder_pkg_sync => sub { _sync($app, @_) });
}

sub _sync {
    my ($app, $job, $path, $recurs) = @_;
    return $job->fail('Empty path is not allowed') unless $path;
    return $job->fail('Trailing slash is forbidden') if '/' eq substr($path,-1) && $path ne '/';

    my $minion = $app->minion;
    return $job->finish('Previous folder pkg sync job is still active')
        unless my $guard = $minion->guard('folder_pkg_sync' . $path, 360);

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

    return $job->finish('not dir') unless ($root->is_dir($realpath));

    my $folder = $schema->resultset('Folder')->find({path => $realpath});
    return $job->finish("not found") unless $folder;

    my $folder_id = $folder->id;
    my $cnt_created = 0;
    my $cnt_updated = 0;
    my $cnt_deleted = 0;

    my %dbpkgids = ();

    my $rows = $schema->resultset('File')->find_pkgs($folder_id);
    my $rsPkg = $schema->resultset('Pkg');
    my $rsMetapkg = $schema->resultset('Metapkg');
    my $dbPkgs = $rsPkg->select_for_folder($folder_id);
    for my $id (sort keys %$dbPkgs) {
        my $dbpkg = $dbPkgs->{$id};
        $dbpkgids{$dbpkg->{name}} = $id;
    }

    my %idstodelete = %dbpkgids;
    for my $id (sort keys %$rows) {
        my $file = $rows->{$id};
        my $basename = $file->{basename};
        my ($pkg, $version, $build, $arch, $ext) = Directory::Scanner::OBSMediaVersion::parse_pkg($basename);
        next unless $pkg;
        if ($dbpkgids{$pkg}) {
            delete $idstodelete{$pkg}; # we cannot delete from %dbpkgids because there might be multiple packages
            $cnt_updated++;
        } else {
            my $metapkg;
            eval {
                $metapkg = $rsMetapkg->find_or_create({name => $pkg});
            } or do {
                $metapkg = $rsMetapkg->find_or_create({name => $pkg}) unless $metapkg;
            };

            $rsPkg->insert($metapkg->id, $arch, $ext, $folder_id, "");
            $cnt_created++;
        }
    }

    $job->note(cnt_created => $cnt_created, cnt_updated => $cnt_updated);
    if(my @idstodelete = sort values %idstodelete) {

        $schema->storage->dbh->do(
          sprintf(
            'DELETE FROM pkg WHERE folder_id = ? and metapkg_id IN(%s)',
            join ',', ('?') x @idstodelete
          ),
          {},
          ($folder_id, @idstodelete),
        );
        $job->note(cnt_deleted => scalar(@idstodelete));
    };

}

1;
