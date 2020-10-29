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
    my ($self, $country, $folder_id, $file, $capability, $ipv) = @_;
    $capability = 'http' unless $capability;
    $ipv = 'ipv4' unless $ipv;
    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    # currently the query will select rows for both ipv4 and ipv6 if a mirror supports both formats
    # it is not big deal, but can be optimized so only one such row is selected
    my $sql = <<'END_SQL';
select 
    concat(
       x.capability,
       '://',s.hostname,s.urldir) as url,
case when (y.capability = a.cap and chk6.success) then 0 when (y.capability = a.cap and chk6.success is NULL) then 1 when (y.capability = a.cap) then 2 when chk6.success then 3 when chk6.success is NULL then 4 else 5 end as rank1,
case when (x.capability = b.cap and chk.success) then 0 when (x.capability = b.cap and chk.success is NULL) then 1 when chk.success then 3 when chk.success is NULL then 4 else 5 end as rank2,
now() - chk.dt as rank3
from
(select ?::server_capability_t as cap) a
join (select ?::server_capability_t as cap) b on 1 = 1
join (select 'http'::server_capability_t as capability union select 'https'::server_capability_t) x on 1 = 1
join (select 'ipv4'::server_capability_t as capability union select 'ipv6'::server_capability_t) y on 1 = 1
join server s on s.enabled
left join server_capability_check chk on chk.server_id = s.id and chk.capability = x.capability
left join server_capability_check chk_old on chk_old.server_id = s.id and chk_old.capability = x.capability and chk_old.dt > chk.dt
left join server_capability_check chk6 on chk6.server_id = s.id and chk6.capability = y.capability
left join server_capability_check chk_old6 on chk_old6.server_id = s.id and chk_old6.capability = y.capability and chk_old6.dt > chk6.dt
left join server_capability_declaration cap  on cap.server_id   = s.id and cap.capability   = x.capability and not cap.enabled
left join server_capability_declaration cap6 on cap6.server_id  = s.id and cap6.capability  = y.capability and not cap6.enabled
left join server_capability_force      fcap  on fcap.server_id  = s.id and fcap.capability  = x.capability
left join server_capability_force      fcap6 on fcap6.server_id = s.id and fcap6.capability = y.capability
left join server_capability_declaration cap_asn_only on s.id = cap_asn_only.server_id and cap_asn_only.capability = 'as_only'
join folder_diff_server fds on fds.server_id = s.id
join folder_diff fd on fd.id = fds.folder_diff_id
join file fl on fl.folder_id = ? and fl.name = ? and fl.folder_id = fd.folder_id and fl.dt <= fd.dt
left join folder_diff_file fdf on fdf.file_id = fl.id and fdf.folder_diff_id = fd.id
where fdf.file_id is NULL
and fcap.server_id is NULL
and fcap6.server_id is NULL
and cap.server_id is NULL
and cap6.server_id is NULL
and cap_asn_only.server_id is NULL
and s.country = lower(?)
and chk_old.server_id IS NULL
and chk_old6.server_id IS NULL
order by rank1, rank2, rank3
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute($ipv, $capability, $folder_id, $file, $country);
    my $server_arrayref = $dbh->selectall_arrayref($prep, { Slice => {} });
    return $server_arrayref;
}

sub folder {
    my ($self, $id, $country) = @_;
    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;
    $country = "" unless $country;

    my $country_condition = "";
    $country_condition = "and s.country = lower(?)" if $country;

    my $sql = <<'END_SQL';
select s.id as server_id, 
concat(
    case 
        when (cap_http.server_id is null and cap_fhttp.server_id is null) then 'http'
        else 'https'
    end
,'://',s.hostname,s.urldir,f.path) as url, max(fds.folder_diff_id) as diff_id 
from server s join folder f on f.id=? 
left join server_capability_declaration cap_http  on cap_http.server_id  = s.id and cap_http.capability  = 'http' and not cap_http.enabled
left join server_capability_declaration cap_https on cap_https.server_id = s.id and cap_https.capability = 'https' and not cap_https.enabled
left join server_capability_force cap_fhttp  on cap_fhttp.server_id  = s.id and cap_fhttp.capability  = 'http'
left join server_capability_force cap_fhttps on cap_fhttps.server_id = s.id and cap_fhttps.capability = 'https'
left join folder_diff fd on fd.folder_id = f.id
left join folder_diff_server fds on fd.id = fds.folder_diff_id and fds.server_id=s.id  
where 
(fds.folder_diff_id IS NOT DISTINCT FROM fd.id OR fds.server_id is null)
AND (cap_fhttp.server_id IS NULL or cap_fhttps.server_id IS NULL)
END_SQL

    $sql = $sql . $country_condition . ' group by s.id, s.hostname, s.urldir, f.path, cap_http.server_id, cap_fhttp.server_id order by s.id';

    my $prep = $dbh->prepare($sql);
    if ($country) {
        $prep->execute($id, $country);
    } else {
        $prep->execute($id);
    }
    my $server_arrayref = $dbh->selectall_arrayref($prep, { Slice => {} });
    return $server_arrayref;
}

1;
