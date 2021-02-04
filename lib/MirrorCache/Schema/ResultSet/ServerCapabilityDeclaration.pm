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

package MirrorCache::Schema::ResultSet::ServerCapabilityDeclaration;

use strict;
use warnings;

use base 'DBIx::Class::ResultSet';

sub search_by_country {
    my ($self, $country) = @_;
    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = <<'END_SQL';
select concat(s.hostname,s.urldir) as uri, s.hostname as hostname, s.id as id,
    -- server has capability enabled when two conditions are true:
    -- 1. server_id is not mentioned in server_capability_force
    -- 2. there is no entry in server_capability_declaration which has enabled='F' for the server_id.
    COALESCE(fhttp.server_id  = 0, COALESCE(http.enabled,'t'))  as http,
    COALESCE(fhttps.server_id = 0, COALESCE(https.enabled,'t')) as https,
    COALESCE(fipv4.server_id  = 0, COALESCE(ipv4.enabled,'t'))  as ipv4,
    COALESCE(fipv6.server_id  = 0, COALESCE(ipv6.enabled,'t'))  as ipv6
    from server s
    left join server_capability_declaration http  on http.server_id  = s.id and http.capability  = 'http'
    left join server_capability_declaration https on https.server_id = s.id and https.capability = 'https'
    left join server_capability_declaration ipv4  on ipv4.server_id  = s.id and ipv4.capability  = 'ipv4'
    left join server_capability_declaration ipv6  on ipv6.server_id  = s.id and ipv4.capability  = 'ipv6'
    left join server_capability_force fhttp  on fhttp.server_id  = s.id and fhttp.capability  = 'http'
    left join server_capability_force fhttps on fhttps.server_id = s.id and fhttps.capability = 'https'
    left join server_capability_force fipv4  on fipv4.server_id  = s.id and fipv4.capability  = 'ipv4'
    left join server_capability_force fipv6  on fipv6.server_id  = s.id and fipv6.capability  = 'ipv6'
    where 't'
    AND (fhttp.server_id IS NULL or fhttps.server_id IS NULL) -- do not show servers which have both http and https force disabled
    AND (fipv4.server_id IS NULL or fipv6.server_id IS NULL)  -- do not show servers which have both ipv4 and ipv6 force disabled    
    AND s.country = lower(?)
    AND s.enabled
END_SQL
    return $dbh->selectall_hashref($sql, 'id', {}, $country);
}

sub log_probe_outcome {
    my ($self, $server_id, $capability, $success, $error) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = <<'END_SQL';
insert into server_capability_check(server_id, capability, dt, success, extra)
values (?, ?, now(), ?, ?);
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute($server_id, $capability, $success, $error);
}

sub search_all_downs {
    my ($self, $country) = @_;
    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = <<'END_SQL';
select c.server_id as id, c.capability, concat(s.hostname,s.urldir) as uri
from server_capability_check c
    join server s on c.server_id = s.id
    left join server_capability_force f on f.server_id  = s.id and f.capability  = c.capability
where 't'
    AND f.server_id IS NULL
    AND c.dt > now() - interval '2 hour'
    AND s.enabled
group by c.server_id, c.capability, s.hostname, s.urldir
having   sum(case when not c.success then 1 else 0 end) >= 5 and 
         sum(case when c.success then 1 else -1 end) < 0
END_SQL
    return $dbh->selectall_hashref($sql, 'id', {});
}

sub force_down {
    my ($self, $server_id, $capability, $error) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = <<'END_SQL';
insert into server_capability_force(server_id, capability, dt, extra)
values (?, ?, now(), ?);
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute($server_id, $capability, $error);
}

sub search_all_forced {
    my ($self, $country) = @_;
    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = <<'END_SQL';
select f.server_id as id, f.capability, concat(s.hostname,s.urldir) as uri
from server_capability_force f
    join server s on f.server_id = s.id
where 't'
    AND f.dt < now() - interval '2 hour'
    AND s.enabled
END_SQL
    return $dbh->selectall_hashref($sql, 'id', {});
}

sub force_up {
    my ($self, $server_id, $capability) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = <<'END_SQL';
delete from server_capability_force where server_id = ? and capability = ?
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute($server_id, $capability);
}

1;
