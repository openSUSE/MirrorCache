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

package MirrorCache::Schema::ResultSet::FolderDiffServer;

use strict;
use warnings;

use base 'DBIx::Class::ResultSet';

sub update_diff_id {
    my $self = shift;
    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;
    my $sql = "update folder_diff_server set folder_diff_id = ? where server_id = ? and folder_diff_id = ?";

    my $prep = $dbh->prepare($sql);
    $prep->execute(@_);
}

1;
