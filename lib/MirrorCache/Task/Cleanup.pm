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

package MirrorCache::Task::Cleanup;
use Mojo::Base 'Mojolicious::Plugin';

sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(cleanup => sub { _run($app, @_) });
}

sub _run {
    my ($app, $job) = @_;
    my $minion = $app->minion;
    return $job->finish('Previous cleanup job is still active')
      unless my $guard = $minion->guard('cleanup', 120);

    my $schema = $app->schema;

    # purge unreferenced folder_diff
    my $sql = <<'END_SQL';
with DiffToDelete as (
   select fd.id 
   from folder_diff fd 
   left join folder_diff_server fds on fds.folder_diff_id = fd.id 
   where 
   fds.folder_diff_id is null
   and fd.dt < current_timestamp - interval '2 day'
   limit 1000
 ),
FilesDeleted as (
   delete from folder_diff_file where folder_diff_id in
   (select * from DiffToDelete))
delete from folder_diff where id in 
   (select * from DiffToDelete)
END_SQL

    eval {
        $schema->storage->dbh->prepare($sql)->execute();
        1;
    } or $job->note(last_warning => $@);
    
    return $job->retry({delay => 60});
}

1;
