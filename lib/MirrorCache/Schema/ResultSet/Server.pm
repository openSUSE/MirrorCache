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

package MirrorCache::Schema::ResultSet::Server;

use strict;
use warnings;

use base 'DBIx::Class::ResultSet';

sub mirrors_country {
    my ($self, $country, $folder, $file) = @_;
    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = <<'END_SQL';
select concat('http://',s.hostname,s.urldir) as url
from server s
left join server_capability cap_asn_only on s.id = cap_asn_only.server_id and cap_asn_only.capability = 'as_only'
join folder_diff_server fds on fds.server_id = s.id
join folder_diff fd on fd.id = fds.folder_diff_id
join folder f on f.id = fd.folder_id and f.path = ?
join file fl on fl.folder_id = f.id and fl.name = ? and fl.dt <= fd.dt
left join folder_diff_file fdf on fdf.file_id = fl.id and fdf.folder_diff_id = fd.id
where fdf.file_id is NULL
and cap_asn_only.server_id is NULL
and s.country = lower(?)
and s.enabled
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute($folder, $file, $country);
    my $server_arrayref = $dbh->selectall_arrayref($prep, { Slice => {} });
    return $server_arrayref;
}

sub folder {
    my ($self, $id) = @_;
    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = "select s.id as server_id, concat('http://',s.hostname,s.urldir,f.path) as url from server s join folder f on f.id=? left join folder_diff fd on fd.folder_id = f.id left join folder_diff_server fds on fd.id = fds.folder_diff_id and server_id=s.id";

    my $prep = $dbh->prepare($sql);
    $prep->execute($id);
    my $server_arrayref = $dbh->selectall_arrayref($prep, { Slice => {} });
    return $server_arrayref;
}

1;
