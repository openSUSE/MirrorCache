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

package MirrorCache::Schema::ResultSet::Folder;

use strict;
use warnings;

use base 'DBIx::Class::ResultSet';

sub get_db_sync_queue_position {
    my ($self, $path) = @_;
    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = <<'END_SQL';
select 1+count(*) as cnt
from folder f
where f.db_sync_scheduled > (select db_sync_scheduled from folder f1 where path = ?)
and f.db_sync_priority >= (select db_sync_priority from folder f1 where path = ?)
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute($path, $path);
    return $dbh->selectrow_array($prep);
}

sub request_db_sync {
    my ($self, $path, $priority) = @_;
    $priority = 10 unless $priority;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    # TODO increase priority if exists
#    my $sql = <<'END_SQL';
# update folder set 
# db_sync_scheduled = now(), 
# db_sync_priority = ? 
# where path = ? and 
# db_sync_scheduled < db_sync_last
# END_SQL

    my $sql = <<'END_SQL';
insert into folder(path, db_sync_scheduled)
values (?, now() at time zone 'UTC')
on conflict(path) do update set
db_sync_scheduled = case when folder.db_sync_scheduled > folder.db_sync_last then now() at time zone 'UTC' else folder.db_sync_scheduled end,
db_sync_priority = ?
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute($path, $priority);
}

1;
