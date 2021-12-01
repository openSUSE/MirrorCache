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

package MirrorCache::Schema::ResultSet::File;

use strict;
use warnings;

use base 'DBIx::Class::ResultSet';

sub find_with_hash {
    my ($self, $folder_id, $name) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    # html parser may loose seconds from file.mtime, so we allow hash.mtime differ for up to 1 min for now
    my $sql = <<'END_SQL';
select file.id, file.folder_id, file.name,
case when coalesce(file.size, 0::bigint)  = 0::bigint and coalesce(hash.size, 0::bigint)  != 0::bigint then hash.size else file.size end,
case when coalesce(file.mtime, 0::bigint) = 0::bigint and coalesce(hash.mtime, 0::bigint) != 0::bigint then hash.mtime else file.mtime end,
file.mtime, file.dt, hash.mtime as hash_mtime, hash.md5, hash.sha1, hash.sha256, hash.piece_size, hash.pieces,
(DATE_PART('day',    now() - file.dt) * 24 * 3600 +
 DATE_PART('hour',   now() - file.dt) * 3600 +
 DATE_PART('minute', now() - file.dt) * 60 +
 DATE_PART('second', now() - file.dt)) as age
from file
left join hash on file_id = id and
(
  (file.size = hash.size and abs(file.mtime - hash.mtime) < 61)
  or
  (coalesce(file.size, 0::bigint) = 0::bigint and coalesce(hash.size, 0::bigint) != 0::bigint and file.dt <= hash.dt)
)
where file.folder_id = ? and name = ?
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute($folder_id, $name);
    return $dbh->selectrow_hashref($prep);
}

# returns list of file_id for which we need hash to (re)calculate
sub hash_needed {
    my ($self, $folder_id, $dt) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    unless ($dt) {
        my $res = $self->need_hashes($folder_id);
        $dt = $res->{max_dt} if $res;
    }

    my $sql = <<'END_SQL';
select file.id, file.name, file.size
from file
left join hash on file_id = id
where file.folder_id = ?
and (hash.file_id is null or coalesce(file.dt > ?, 't'))
END_SQL
    return $dbh->selectall_hashref($sql, 'id', {}, $folder_id, $dt);
}

# returns pair (bool, max_dt)
sub need_hashes {
    my ($self, $folder_id) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = <<'END_SQL';
select file.id,
(select max(hash.dt) from hash join file on file_id = id where folder_id = ?) as max_dt
from file
left join hash on file_id = id
where file.folder_id = ?
and (hash.file_id is null or coalesce(file.dt > hash.dt, 't'))
limit 1;
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute($folder_id, $folder_id);
    return $dbh->selectrow_hashref($prep);
}

1;
