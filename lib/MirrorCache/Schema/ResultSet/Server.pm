# Copyright (C) 2020,2021 SUSE LLC
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

sub mirrors_query {
    my (
        $self, $country, $region, $folder_id,       $file_id, $capability,
        $ipv,  $lat,     $lng,    $avoid_countries, $limit,   $avoid_region,
        $schemastrict, $ipvstrict, $vpn
    ) = @_;
    $country    = ''     unless $country;
    $region     = ''     unless $region;
    $capability = 'http' unless $capability;
    $ipv        = 'ipv4' unless $ipv;
    $lat        = 0      unless $lat;
    $lng        = 0      unless $lng;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $avoid_country = $avoid_region;
    my $country_condition;
    my @country_params = ($country);
    $avoid_region = ($region && $avoid_region) ? '!' : '';
    if ($avoid_countries && (my @list = @$avoid_countries)) {
        $avoid_country = ($country && grep { $country eq $_ } @list) ? '!' : '';
        my $placeholder = join(',' => ('?') x scalar @list);
        $country_condition = "and s.country not in ($placeholder)";
        @country_params    = @list;
        if ($country) {
            $avoid_country = $avoid_country || $avoid_region ? '!' : '';
            $country_condition .= " and s.country $avoid_country= lower(?)";
            push(@country_params, $country);
        }
        if ($region) {
            $country_condition .= " and s.region $avoid_region= ?";
            push(@country_params, $region);
        }
    }
    elsif ($country) {
        $avoid_country = $avoid_country ? '!' : '';
        my $region_condition = '';
        if ($region) {
            $region_condition = " and s.region $avoid_region= ?";
            @country_params   = ($country, $region);
        }
        $country_condition = " and ( s.country $avoid_country= lower(?) $region_condition)";
    }
    else {
        $country_condition = "";
        @country_params    = ();
        if ($region) {
            $country_condition = " and s.region $avoid_region= ?";
            @country_params    = ($region);
        }
    }
    my $weight_country_case = ($avoid_country or $avoid_region) ? '' : "when country $avoid_country= '$country' then 2 ";
    my $ipvx = $ipv eq 'ipv4'? 'ipv6' : 'ipv4';
    my $capabilityx = $capability eq 'http'? 'https' : 'http';
    my $extra = '';
    if ($schemastrict && $ipvstrict) {
       $extra = "AND support_scheme > 0 and support_ipv > 0";
    } elsif ($schemastrict) {
       $extra = "AND support_scheme > 0";
    } elsif ($ipvstrict) {
       $extra = "AND support_ipv > 0";
    }
    my $hostname = $vpn? "CASE WHEN length(s.hostname_vpn)>0 THEN s.hostname_vpn ELSE s.hostname END" : "s.hostname";

    my $sql = <<"END_SQL";
select * from (
select x.id as mirror_id, concat(case when support_scheme > 0 then '$capability' else '$capabilityx' end, '://', uri) as url,
dist,
case $weight_country_case when region $avoid_region= '$region' then 1 else 0 end rating_country,
score, country, region, lng,
support_scheme,
rating_scheme,
support_ipv,
rating_ipv
from (
select s.id,
    concat($hostname,s.urldir,f.path,'/',s.name) as uri,
s.lat as lat,
s.lng as lng,
case when $lat=0 and $lng=0 then 0
else
( 6371 * acos( cos( radians($lat) ) * cos( radians( lat ) ) * cos( radians( lng ) - radians($lng) ) + sin( radians($lat) ) * sin( radians( lat ) ) ) )
end as dist,
s.country, s.region, s.score,
CASE WHEN COALESCE(stability_scheme.rating, 0) > 0 OR COALESCE(stability_schemex.rating, 0) = 0 THEN 1 ELSE 0 END AS support_scheme, -- we show here 0 only when opposite scheme is supported
CASE WHEN COALESCE(stability_scheme.rating, 0) > 0 OR COALESCE(stability_schemex.rating, 0) = 0 THEN ( scf.capability is NULL AND COALESCE(scd.enabled, 't') = 't' ) ELSE ( scf2.capability is NULL AND COALESCE(scd2.enabled, 't') = 't' ) END AS not_disabled,
CASE WHEN COALESCE(stability_scheme.rating, 0) > 0 THEN stability_scheme.rating WHEN COALESCE(stability_schemex.rating, 0) > 0 THEN stability_schemex.rating ELSE 0 END AS rating_scheme,
CASE WHEN COALESCE(stability_ipv.rating, 0)    > 0 THEN 1 ELSE 0 END AS support_ipv,
CASE WHEN COALESCE(stability_ipv.rating, 0)    > 0 THEN stability_ipv.rating    WHEN COALESCE(stability_ipvx.rating, 0)    > 0 THEN stability_ipvx.rating    ELSE 0 END AS rating_ipv
from (
    select s.*, fl.name
    from folder_diff fd
    join file fl on fl.id = ?
    join folder_diff_server fds on fd.id = fds.folder_diff_id and fl.dt <= fds.dt
    join server s on fds.server_id = s.id and s.enabled  $country_condition
    left join folder_diff_file fdf on fdf.file_id = fl.id and fdf.folder_diff_id = fd.id
    where fd.folder_id = ? and fdf.file_id is NULL
) s
join folder f on f.id = ?
left join server_capability_declaration scd  on s.id = scd.server_id and scd.capability = '$capability' and NOT scd.enabled
left join server_capability_force scf        on s.id = scf.server_id and scf.capability = '$capability'
left join server_capability_declaration scd2 on s.id = scd2.server_id and scd.capability = '$ipv' and NOT scd.enabled
left join server_capability_force scf2       on s.id = scf2.server_id and scf2.capability = '$ipv'
left join server_stability stability_scheme  on s.id = stability_scheme.server_id  and stability_scheme.capability = '$capability'
left join server_stability stability_schemex on s.id = stability_schemex.server_id and stability_schemex.capability = '$capabilityx'
left join server_stability stability_ipv     on s.id = stability_ipv.server_id     and stability_ipv.capability = '$ipv'
left join server_stability stability_ipvx    on s.id = stability_ipvx.server_id    and stability_ipvx.capability = '$ipvx'
) x
WHERE not_disabled $extra
order by rating_country desc, (dist/100)::int, support_scheme desc, rating_scheme desc, support_ipv desc, rating_ipv desc, score, random()
limit (case when $limit > 10 then $limit+$limit else 10 end)
) xx
order by support_scheme desc, rating_scheme desc, support_ipv desc, rating_ipv desc, rating_country desc, (dist/100)::int, score, random()
limit $limit;
END_SQL
    my $prep = $dbh->prepare($sql);

    $prep->execute($file_id, @country_params, $folder_id, $folder_id);
    my $server_arrayref = $dbh->selectall_arrayref($prep, { Slice => {} });
    return $server_arrayref;
}

sub folder {
    my ($self, $id) = @_;
    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = <<'END_SQL';
select s.id as server_id,
concat(
    case
        when (cap_http.server_id is null and cap_fhttp.server_id is null) then 'http'
        else 'https'
    end,
    '://',
    CASE WHEN length(s.hostname_vpn)>0 THEN s.hostname_vpn ELSE s.hostname END,
    s.urldir,f.path) as url,
max(fds.folder_diff_id) as diff_id, extract(epoch from max(fd.dt)) as dt_epoch,
cap_hasall.capability as hasall
from server s join folder f on f.id=?
left join server_capability_declaration cap_http  on cap_http.server_id  = s.id and cap_http.capability  = 'http' and not cap_http.enabled
left join server_capability_declaration cap_https on cap_https.server_id = s.id and cap_https.capability = 'https' and not cap_https.enabled
left join server_capability_force cap_fhttp  on cap_fhttp.server_id  = s.id and cap_fhttp.capability  = 'http'
left join server_capability_force cap_fhttps on cap_fhttps.server_id = s.id and cap_fhttps.capability = 'https'
left join folder_diff fd on fd.folder_id = f.id
left join folder_diff_server fds on fd.id = fds.folder_diff_id and fds.server_id=s.id
left join server_capability_declaration cap_hasall on cap_hasall.server_id  = s.id and cap_hasall.capability  = 'hasall' and cap_hasall.enabled
left join project p on f.path like concat(p.path, '%')
left join server_project sp on (sp.server_id, sp.project_id) = (s.id, p.id) and sp.state < 1
where
(fds.folder_diff_id IS NOT DISTINCT FROM fd.id OR fds.server_id is null)
AND (cap_fhttp.server_id IS NULL or cap_fhttps.server_id IS NULL)
AND (sp.server_id IS NULL)
group by s.id, s.hostname, s.urldir, f.path, cap_http.server_id, cap_fhttp.server_id, cap_hasall.capability
order by s.id
END_SQL

    my $prep = $dbh->prepare($sql);
    $prep->execute($id);

    my $server_arrayref = $dbh->selectall_arrayref($prep, { Slice => {} });
    return $server_arrayref;
}

sub server_projects {
    my ($self) = @_;
    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = <<'END_SQL';
select concat(s.id, '::', p.id) as key,
        s.id as server_id,
        p.id as project_id,
        concat(CASE WHEN length(s.hostname_vpn)>0 THEN s.hostname_vpn ELSE s.hostname END,s.urldir, p.path) as uri,
        sp.server_id as mirror_id,
        coalesce(sp.state, -2) oldstate
from project p
    join server s on s.enabled
    left join server_project sp on sp.server_id = s.id and sp.project_id = p.id
where 't'
    AND coalesce(sp.state,0) > -1
END_SQL
    return $dbh->selectall_hashref($sql, 'key', {});
}

sub log_project_probe_outcome {
    my ($self, $server_id, $project_id, $mirror_id, $state, $extra) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = <<'END_SQL';
insert into server_project(state, extra, dt, server_id, project_id)
values (?, ?, now(), ?, ?);
END_SQL

    if ($mirror_id) {
        $sql = <<'END_SQL';
update server_project set state = ?, extra = ?, dt = now()
where server_id = ? and project_id = ?;
END_SQL
    }

    my $prep = $dbh->prepare($sql);
    $prep->execute($state, $extra, $server_id, $project_id);
}

1;
