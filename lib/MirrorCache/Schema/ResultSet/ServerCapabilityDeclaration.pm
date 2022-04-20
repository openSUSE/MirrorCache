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
select concat(CASE WHEN length(s.hostname_vpn)>0 THEN s.hostname_vpn ELSE s.hostname END,s.urldir,'/') as uri, CASE WHEN length(s.hostname_vpn)>0 THEN s.hostname_vpn ELSE s.hostname END as hostname, s.id as id,
    -- server has capability enabled when two conditions are true:
    -- 1. server_id is not mentioned in server_capability_force
    -- 2. there is no entry in server_capability_declaration which has enabled='F' for the server_id.
    COALESCE(fhttp.server_id  = 0, COALESCE(http.enabled,'t'))  as http,
    COALESCE(fhttps.server_id = 0, COALESCE(https.enabled,'t')) as https,
    COALESCE(fipv4.server_id  = 0, COALESCE(ipv4.enabled,'t'))  as ipv4,
    COALESCE(fipv6.server_id  = 0, COALESCE(ipv6.enabled,'t'))  as ipv6,
    stability_http.rating  as rating_http,
    stability_https.rating as rating_https,
    stability_ipv4.rating  as rating_ipv4,
    stability_ipv6.rating  as rating_ipv6,
    extract(epoch from (now() - check_http.dt))*1000 :: int  as ms_http,
    extract(epoch from (now() - check_https.dt))*1000 :: int  as ms_https,
    extract(epoch from (now() - check_ipv4.dt))*1000 :: int  as ms_ipv4,
    extract(epoch from (now() - check_ipv6.dt))*1000 :: int  as ms_ipv6
    from server s
    left join server_capability_declaration http  on http.server_id  = s.id and http.capability  = 'http'
    left join server_capability_declaration https on https.server_id = s.id and https.capability = 'https'
    left join server_capability_declaration ipv4  on ipv4.server_id  = s.id and ipv4.capability  = 'ipv4'
    left join server_capability_declaration ipv6  on ipv6.server_id  = s.id and ipv6.capability  = 'ipv6'
    left join server_capability_force fhttp  on fhttp.server_id  = s.id and fhttp.capability  = 'http'
    left join server_capability_force fhttps on fhttps.server_id = s.id and fhttps.capability = 'https'
    left join server_capability_force fipv4  on fipv4.server_id  = s.id and fipv4.capability  = 'ipv4'
    left join server_capability_force fipv6  on fipv6.server_id  = s.id and fipv6.capability  = 'ipv6'
    left join server_stability stability_http  on stability_http.server_id  = s.id and stability_http.capability  = 'http'
    left join server_stability stability_https on stability_https.server_id = s.id and stability_https.capability = 'https'
    left join server_stability stability_ipv4  on stability_ipv4.server_id  = s.id and stability_ipv4.capability  = 'ipv4'
    left join server_stability stability_ipv6  on stability_ipv6.server_id  = s.id and stability_ipv6.capability  = 'ipv6'
    left join (
        select server_id, max(dt) as dt from server_capability_check x where x.capability  = 'http'  and dt > now() - interval '24 hours' group by server_id
    ) check_http  on check_http.server_id = s.id
    left join (
        select server_id, max(dt) as dt from server_capability_check x where x.capability  = 'https' and dt > now() - interval '24 hours' group by server_id
    ) check_https on check_https.server_id = s.id
    left join (
        select server_id, max(dt) as dt from server_capability_check x where x.capability  = 'ipv4'  and dt > now() - interval '24 hours' group by server_id
    ) check_ipv4  on check_ipv4.server_id = s.id
    left join (
        select server_id, max(dt) as dt from server_capability_check x where x.capability  = 'ipv6'  and dt > now() - interval '24 hours' group by server_id
    ) check_ipv6  on check_ipv6.server_id = s.id
    where
        (fhttp.server_id IS NULL or fhttps.server_id IS NULL) -- do not show servers which have both http and https force disabled
    AND (fipv4.server_id IS NULL or fipv6.server_id IS NULL)  -- do not show servers which have both ipv4 and ipv6 force disabled
    AND s.enabled
END_SQL

    unless ($dbh->{Driver}->{Name} eq 'Pg') {
        $sql =~ s/'t'/1/g;
        $sql =~ s/extract\(epoch from \(now\(\) - /TIMESTAMPDIFF(MICROSECOND, /g;
        $sql =~ s/dt \> now\(\) - interval '24 hours'/TIMESTAMPDIFF(HOUR, dt, CURRENT_TIMESTAMP(3)) < 24/g;
        $sql =~ s/\)\)\*1000 :: int/, CURRENT_TIMESTAMP(3))\/1000/g;
    }

    return $dbh->selectall_hashref($sql, 'id', {}) unless $country;

    $sql = $sql . ' AND s.country = lower(?)';
    return $dbh->selectall_hashref($sql, 'id', {}, $country);
}

sub insert_stability_row {
    my ($self, $server_id, $capability) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = <<'END_SQL';
insert into server_stability(server_id, capability, rating, dt)
values (?, ?, 1, CURRENT_TIMESTAMP(3))
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute($server_id, $capability);
}

sub reset_stability {
    my ($self, $server_id, $capability, $error) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = <<'END_SQL';
update server_stability
set dt = CURRENT_TIMESTAMP(3), rating = 0
where server_id = ? and capability = ?
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute($server_id, $capability);

    $sql = <<'END_SQL';
insert into server_capability_check(server_id, capability, dt, extra)
values (?, ?, CURRENT_TIMESTAMP(3), ?);
END_SQL
    $prep = $dbh->prepare($sql);
    $prep->execute($server_id, $capability, $error);
}

sub update_stability {
    my ($self, $server_id, $capability, $rating) = @_;
    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = <<'END_SQL';
update server_stability
set dt = CURRENT_TIMESTAMP(3), rating = ?
where server_id = ? and capability = ?
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute($rating, $server_id, $capability);
}

sub search_all_downs {
    my ($self, $country) = @_;
    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = <<'END_SQL';
select concat(c.server_id,c.capability) as _key,
       c.server_id as id, c.capability, concat(CASE WHEN length(s.hostname_vpn)>0 THEN s.hostname_vpn ELSE s.hostname END,s.urldir) as uri
from server_capability_check c
    join server s on c.server_id = s.id
    left join server_capability_force f on f.server_id  = s.id and f.capability  = c.capability
where
        f.server_id IS NULL
    AND c.dt > now() - interval '2 hour'
    AND s.enabled
group by c.server_id, c.capability, s.hostname, s.hostname_vpn, s.urldir
having   count(*) >= 5
END_SQL
    $sql =~ s/now\(\) - interval '2 hour'/date_sub(CURRENT_TIMESTAMP(3), interval 2 hour)/g unless $dbh->{Driver}->{Name} eq 'Pg';

    return $dbh->selectall_hashref($sql, '_key', {});
}

sub force_down {
    my ($self, $server_id, $capability, $error) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = <<'END_SQL';
insert into server_capability_force(server_id, capability, dt, extra)
values (?, ?, CURRENT_TIMESTAMP(3), ?);
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
select concat(f.server_id, f.capability) as _key,
       f.server_id as id, f.capability, concat(CASE WHEN length(s.hostname_vpn)>0 THEN s.hostname_vpn ELSE s.hostname END,s.urldir) as uri
from server_capability_force f
    join server s on f.server_id = s.id
where
        f.dt < now() - interval '2 hour'
    AND s.enabled
END_SQL

    $sql =~ s/now\(\) - interval '2 hour'/date_sub(CURRENT_TIMESTAMP(3), interval 2 hour)/g unless $dbh->{Driver}->{Name} eq 'Pg';

    return $dbh->selectall_hashref($sql, '_key', {});
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
