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

package MirrorCache::Schema::ResultSet::Hash;

use strict;
use warnings;

use base 'DBIx::Class::ResultSet';
use DBI qw(:sql_types);

sub store {
    my ($self, $file_id, $mtime, $size, $md5hex, $sha1hex, $sha256hex, $sha512hex, $block_size, $pieceshex, $zlengths, $zblock_size, $zhashes, $target) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql;
if ($dbh->{Driver}->{Name} eq 'Pg') {
    $sql = <<'END_SQL';
insert into hash(file_id, mtime, size, md5, sha1, sha256, sha512, piece_size, pieces, zlengths, zblock_size, zhashes, target, dt)
values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, now())
ON CONFLICT (file_id) DO UPDATE
  SET size   = excluded.size,
      mtime  = excluded.mtime,
      md5    = excluded.md5,
      sha1   = excluded.sha1,
      sha256 = excluded.sha256,
      sha512 = excluded.sha512,
      piece_size  = excluded.piece_size,
      pieces      = excluded.pieces,
      zlengths    = excluded.zlengths,
      zblock_size = excluded.zblock_size,
      zhashes     = excluded.zhashes,
      target      = excluded.target,
      dt = now()
END_SQL
} else {
    $sql = <<'END_SQL';
insert into hash(file_id, mtime, size, md5, sha1, sha256, sha512, piece_size, pieces, zlengths, zblock_size, zhashes, target, dt)
values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP(3))
ON DUPLICATE KEY UPDATE
      size   = values(size),
      mtime  = values(mtime),
      md5    = values(md5),
      sha1   = values(sha1),
      sha256 = values(sha256),
      sha512 = values(sha512),
      piece_size  = values(piece_size),
      pieces      = values(pieces),
      zlengths    = values(zlengths),
      zblock_size = values(zblock_size),
      zhashes     = values(zhashes),
      target      = values(target),
      dt = CURRENT_TIMESTAMP(3)
END_SQL
}
    my $prep = $dbh->prepare($sql);
    $prep->bind_param( 1, $file_id,     SQL_BIGINT);
    $prep->bind_param( 2, $mtime,       SQL_BIGINT);
    $prep->bind_param( 3, $size,        SQL_BIGINT);
    $prep->bind_param( 4, $md5hex,      SQL_CHAR);
    $prep->bind_param( 5, $sha1hex,     SQL_CHAR);
    $prep->bind_param( 6, $sha256hex,   SQL_CHAR);
    $prep->bind_param( 7, $sha512hex,   SQL_CHAR);
    $prep->bind_param( 8, $block_size,  SQL_INTEGER);
    $prep->bind_param( 9, $pieceshex,   SQL_VARCHAR);
    $prep->bind_param(10, $zlengths,    SQL_VARCHAR);
    $prep->bind_param(11, $zblock_size, SQL_INTEGER);
    $prep->bind_param(12, $zhashes,     SQL_VARBINARY); # we must force varbinary, otherwise driver will corrupt hashes trying to handle unicode
    $prep->bind_param(13, $target,      SQL_VARCHAR);
    $prep->execute();
}

sub hashes_since {
    my ($self, $folder_id, $time_constraint) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $time_constraint_condition = '';
    my @query_params              = ($folder_id);
    if ($time_constraint) {
        $time_constraint_condition = $time_constraint ? 'and hash.dt >= ?' : '';
        push(@query_params, $time_constraint);
    }

    my $sql = <<"END_SQL";
select file.name, hash.mtime, hash.size, md5, sha1, sha256, sha512, piece_size, pieces, hash.target, hash.dt
from hash left join file on file_id = id
where file_id in ( select id from file where folder_id = ? )
$time_constraint_condition limit 100000
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute(@query_params);
    return $dbh->selectall_arrayref($prep, {Slice => {}});
}

1;
