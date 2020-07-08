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

package MirrorCache::Schema::ResultSet::AuditEvent;

use strict;
use warnings;

use base 'DBIx::Class::ResultSet';
use Mojo::JSON 'from_json';

sub path_misses {
    my ($self, $prev_event_log_id, $limit) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = "select id, event_data from audit_event where name='path_miss'";
    $sql = "$sql and id > $prev_event_log_id" if $prev_event_log_id;
    $sql = "$sql order by id desc";
    $sql = "$sql limit ($limit)" if $limit;

    my $prep = $dbh->prepare($sql);
    $prep->execute();
    my $arrayref = $dbh->selectall_arrayref($prep, { Slice => {} });
    my $id;
    my @paths = ();
    my %seen  = ();
    foreach my $miss ( @$arrayref ) {
        my $event_data = $miss->{event_data};
        next if $seen{$event_data};
        $id = $miss->{id} unless $id;
        $seen{$event_data} = 1;
        push @paths, from_json($event_data);
    }
    return ($id, \@paths);
}

1;
