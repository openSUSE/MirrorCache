# Copyright (C) 2024 SUSE LLC
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

package MirrorCache::Schema::ResultSet::Pkg;

use strict;
use warnings;

use base 'DBIx::Class::ResultSet';

sub select_for_folder {
    my ($self, $folder_id) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;


    my $sql = <<'END_SQL';
select metapkg.name, pkg.id as id, metapkg_id, pkg.arch_id
from pkg
join metapkg on metapkg.id = metapkg_id
where folder_id = ?
END_SQL

    return $dbh->selectall_hashref($sql, 'id', {}, $folder_id);

}

sub insert {
    my ($self, $metapkg_id, $arch, $ext, $folder_id, $repo) = @_;

    my $dbh = $self->result_source->schema->storage->dbh;

    my $sql = 'insert into pkg(metapkg_id, folder_id, t_created) select ?, ?, now()';

    if ($dbh->{Driver}->{Name} eq 'Pg') {
        $sql = $sql . ' on conflict do nothing';
    } else {
        $sql = $sql . ' on duplicate key update id = id';
    }

    $dbh->prepare($sql)->execute($metapkg_id, $folder_id);
    return 1;
}


1;
