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

sub mirrors_query {
    my (
        $self, $country, $region, $folder_id,       $file_id, $capability,
        $ipv,  $lat,     $lng,    $avoid_countries, $limit,   $avoid_region
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

    my $avoid_country;
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
        $avoid_country = $avoid_region ? '!' : '';
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
    # currently the query will select rows for both ipv4 and ipv6 if a mirror supports both formats
    # it is not big deal, but can be optimized so only one such row is selected
    my $sql = <<"END_SQL";
select * from (
select x.id as mirror_id, url,
case when $lat=0 and $lng=0 then 0  -- prefer servers which were checked recently when geoip is unavailable
else
( 6371 * acos( cos( radians($lat) ) * cos( radians( lat ) ) * cos( radians( lng ) - radians($lng) ) + sin( radians($lat) ) * sin( radians( lat ) ) ) )
end as dist,
(2*(yes1 * yes1) - 2*(case when no1 > 10 then no1 * no1 else 10 * no1 end) + (case when yes2 < 5 then yes2 else 5 * yes2 end) - (case when no2 > 10 then no2 * no2 else 10 * no2 end)) weight1,
case $weight_country_case when region $avoid_region= '$region' then 1 else 0 end weight_country,
(yes3 * yes3) - (case when no3 > 5 then no3 * no3 else 5 * no3 end) weight2,
last1, last2, last3, lastdt1, lastdt2, lastdt3, score, country, region, lng
from (
select s.id,
    concat(
        '$capability://',s.hostname,s.urldir) as url,
s.lat as lat,
s.lng as lng,
s.country, s.region, s.score,
sum(case when chk.capability = '$capability' and chk.success then 1 else 0 end)/10 yes1,
sum(case when chk.capability = '$capability' and not chk.success then 1 else 0 end) no1,
sum(case when chk.capability = '$ipv' and chk.success then 1 else 0 end)/10 yes2,
sum(case when chk.capability = '$ipv' and not chk.success then 1 else 0 end) no2,
sum(case when chk.capability = '$ipvx' and chk.success then 1 else 0 end)/10 yes3,
sum(case when chk.capability = '$ipvx' and not chk.success then 1 else 0 end) no3,
(select success from server_capability_check where server_id = s.id and capability = '$capability' order by dt desc limit 1) as last1,
(select success from server_capability_check where server_id = s.id and capability = '$ipv' order by dt desc limit 1) as last2,
(select success from server_capability_check where server_id = s.id and capability = '$ipvx' order by dt desc limit 1) as last3,
(select date_trunc('minute',dt) from server_capability_check where server_id = s.id and capability = '$capability' order by dt desc limit 1) as lastdt1,
(select date_trunc('minute',dt) from server_capability_check where server_id = s.id and capability = '$ipv' order by dt desc limit 1) as lastdt2,
(select date_trunc('minute',dt) from server_capability_check where server_id = s.id and capability = '$ipvx' order by dt desc limit 1) as lastdt3
from (
    select s.*
    from file fl
    join folder_diff fd on fl.folder_id = fd.folder_id
    join folder_diff_server fds on fd.id = fds.folder_diff_id and fl.dt <= fds.dt
    left join folder_diff_file fdf on fdf.file_id = fl.id and fdf.folder_diff_id = fd.id
    join server s on fds.server_id = s.id and s.enabled  $country_condition
    where fl.folder_id = ? and fl.id = ? and fdf.file_id is NULL
) s
left join server_capability_check chk on s.id = chk.server_id
group by s.id, s.country, s.region, s.score, s.hostname, s.urldir, s.lat, s.lng
) x
order by last1 desc nulls last, last2 desc nulls last, weight_country desc, weight1 desc, weight2 desc, score, lastdt1 desc nulls last, lastdt2 desc nulls last, last3 desc, lastdt3 desc, random()
limit $limit
) xx
order by last1 desc nulls last, last2 desc nulls last, weight_country desc, weight1 desc, (dist/100)::int, weight2 desc, score, last3 desc nulls last, dist, random()
limit $limit;
END_SQL
    my $prep = $dbh->prepare($sql);

    $prep->execute(@country_params, $folder_id, $file_id);
    my $server_arrayref = $dbh->selectall_arrayref($prep, { Slice => {} });
    return $server_arrayref;
}

sub folder {
    my ($self, $id, $country, $region) = @_;
    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;
    $country = "" unless $country;

    my $country_condition = "";
    if ($country) {
        $country_condition = "and s.country = lower(?)";
    } elsif ($region) {
        $country_condition = "and s.region = lower(?)";
    }

    my $sql = <<'END_SQL';
select s.id as server_id,
concat(
    case
        when (cap_http.server_id is null and cap_fhttp.server_id is null) then 'http'
        else 'https'
    end
,'://',s.hostname,s.urldir,f.path) as url, max(fds.folder_diff_id) as diff_id, extract(epoch from max(fd.dt)) as dt_epoch
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
    } elsif ($region) {
        $prep->execute($id, $region);
    } else {
        $prep->execute($id);
    }
    my $server_arrayref = $dbh->selectall_arrayref($prep, { Slice => {} });
    return $server_arrayref;
}

1;
