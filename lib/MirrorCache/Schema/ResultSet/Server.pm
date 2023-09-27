# Copyright (C) 2020-2023 SUSE LLC
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

# MariaDB will create temporary disk table for each mirror_query if this is bigger than default
my $MIRRORCACHE_MAX_PATH = int($ENV{MIRRORCACHE_MAX_PATH} // 512);

sub mirrors_query {
    my (
        $self, $country, $region, $folder_id, $file_id, $project_id,
        $capability, $ipv,  $lat,     $lng,    $avoid_countries,
        $limit,   $avoid_region, $schemastrict, $ipvstrict, $vpn
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
    $avoid_country = $avoid_country ? '!' : '';
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

    my $limit1 = 10;
    $limit1 = $limit + $limit if $limit > 10;

    my $join_server_project = "";
    my $condition_server_project = "";
    if ($project_id) {
        $join_server_project = "left join server_project sp on (project_id,sp.server_id) = ($project_id,s.id) and state < 1";
        $condition_server_project = "and sp.server_id IS NULL";
    }

    my $join_file_cond = "fl.folder_id = fd.folder_id";
    my $file_dt = ", max(case when fdf.file_id is null and fl.name ~ '[0-9]' and fl.name not like '%license.tar.gz' and fl.name not like '%info.xml.gz' then fl.mtime else null end) as mtime";
    my $group_by = "group by s.id, s.hostname, s.hostname_vpn, s.urldir, s.region, s.country, s.lat, s.lng, s.score";

    if ($file_id) {
        $join_file_cond = "fl.id = ?";
        $file_dt = ", fl.mtime as mtime";
        $group_by = "";
    }

    my $sql = <<"END_SQL";
select * from (
select x.id as mirror_id,
case when support_scheme > 0 then '$capability' else '$capabilityx' end as scheme,
hostname,
urldir,
mtime,
dist,
case $weight_country_case when region $avoid_region= '$region' then 1 else 0 end rating_country,
score, country, region, lat, lng,
support_scheme,
rating_scheme,
support_ipv,
rating_ipv
from (
select s.id, $hostname as hostname,
    left(concat(s.urldir,f.path),$MIRRORCACHE_MAX_PATH) as urldir,
s.mtime,
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
    select s.id, s.hostname, s.hostname_vpn, s.urldir, s.region, s.country, s.lat, s.lng, s.score $file_dt
    from folder_diff fd
    join file fl on $join_file_cond
    join folder_diff_server fds on fd.id = fds.folder_diff_id and date_trunc('second', fl.dt) <= fds.dt
    join server s on fds.server_id = s.id and s.enabled  $country_condition
    left join server_capability_declaration scd on s.id = scd.server_id and scd.capability = 'country'
    left join folder_diff_file fdf on fdf.file_id = fl.id and fdf.folder_diff_id = fd.id
    $join_server_project
    where fd.folder_id = ? and fdf.file_id is NULL $condition_server_project
    and ( -- here mirrors may be declared to handle only specific countries
        scd.server_id is null
        or
        length(coalesce(?)) > 0 and (
            ( scd.enabled and ? ~ scd.extra )
            or
            ( not scd.enabled and not ? ~ scd.extra)
        )
    )
    $group_by
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
limit $limit1
) xx
order by support_scheme desc, rating_scheme desc, support_ipv desc, rating_ipv desc, rating_country desc, (dist/100)::int, score, random()
limit $limit;
END_SQL

    $sql =~ s/::int//g                                                unless ($dbh->{Driver}->{Name} eq 'Pg');
    $sql =~ s/random/rand/g                                           unless ($dbh->{Driver}->{Name} eq 'Pg');
    $sql =~ s/date_trunc\('second', fl.dt\)/cast(fl.dt as DATETIME)/g unless ($dbh->{Driver}->{Name} eq 'Pg');
    $sql =~ s/ \~ / REGEXP /g                           unless ($dbh->{Driver}->{Name} eq 'Pg');

    my $prep = $dbh->prepare($sql);

    if ($file_id) {
        $prep->execute($file_id, @country_params, $folder_id, $country, $country, $country, $folder_id);
    } else {
        $prep->execute(@country_params, $folder_id, $country, $country, $country, $folder_id);
    }
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

    $sql =~ s/IS NOT DISTINCT FROM/<=>/g             unless ($dbh->{Driver}->{Name} eq 'Pg');
    $sql =~ s/extract\(epoch from /unix_timestamp(/g unless ($dbh->{Driver}->{Name} eq 'Pg');

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
select concat(s.id, '::', p.id) as _key,
        s.id as server_id,
        p.id as project_id,
        concat(CASE WHEN length(s.hostname_vpn)>0 THEN s.hostname_vpn ELSE s.hostname END,s.urldir, p.path) as uri,
        sp.server_id as mirror_id,
        coalesce(sp.state, -2) oldstate
from project p
    join server s on s.enabled
    left join server_project sp on sp.server_id = s.id and sp.project_id = p.id
where
    coalesce(sp.state,0) > -1
END_SQL
    return $dbh->selectall_hashref($sql, '_key', {});
}

sub log_project_probe_outcome {
    my ($self, $server_id, $project_id, $mirror_id, $state, $extra) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = <<'END_SQL';
insert into server_project(state, extra, dt, server_id, project_id)
values (?, ?, CURRENT_TIMESTAMP(3), ?, ?);
END_SQL

    if ($mirror_id) {
        $sql = <<'END_SQL';
update server_project set state = ?, extra = ?, dt = CURRENT_TIMESTAMP(3)
where server_id = ? and project_id = ?;
END_SQL
    }

    my $prep = $dbh->prepare($sql);
    $prep->execute($state, $extra, $server_id, $project_id);
}

sub report_mirrors {
    my ($self, $project, $region) = @_;
    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $where1  = '';
    $where1 = "WHERE REPLACE(prj.name,' ','') = ?" if $project;

    my $sql = <<"END_SQL";
with
etalon as (
    select prj.id project_id, prj.name, f.id as folder_id, fd2.id as diff_id, f.path
    from project prj
    join folder f on f.path like concat(prj.path,'%')
    join folder_diff fd2 on fd2.folder_id = f.id
    join folder_diff_server fds2 on fd2.id = fds2.folder_diff_id and fds2.server_id = prj.etalon
    -- where prj.name = 'repositories'
    $where1
),
project_folder_count as (
    select project_id, count(*) cnt
    from etalon
    group by project_id
)
select s.id, s.region, s.country,
    s.sponsor, s.sponsor_url,
    s.hostname as hostname,
    concat(s.hostname, s.urldir) as url,
    case when (select rating from server_stability where capability = 'http'  and server_id = s.id) > 0 then concat('http://',  s.hostname, '/', s.urldir, '/') else '' end as http_url,
    case when (select rating from server_stability where capability = 'https' and server_id = s.id) > 0 then concat('https://', s.hostname, '/', s.urldir, '/') else '' end as https_url,
    ( select msg from server_note where kind = 'Ftp'   and server_note.hostname = s.hostname order by server_note.dt desc limit 1) as ftp_url,
    ( select msg from server_note where kind = 'Rsync' and server_note.hostname = s.hostname order by server_note.dt desc limit 1) as rsync_url,
    project,
    round(case when project_folder_count.cnt > 3 then s_eq * 100 / project_folder_count.cnt when s_eq =  project_folder_count.cnt then 100 else 50 end, 0) score,
    s_eq, s_ne, victim, project_folder_count.cnt
from (
select
    cmp.project_id,
    cmp.name project,
    cmp.server_id,
    sum(s_eq) s_eq, sum(s_ne) s_ne,
    max(example) victim
from (
    select
        etalon.project_id,
        etalon.name,
        case when etalon.diff_id = fd.id then 1 else 0 end as s_eq,
        case when etalon.diff_id != fd.id or fd.id is null then 1 else 0 end as s_ne,
        case when etalon.diff_id != fd.id or fd.id is null then path else '' end example,
        fds.server_id
    from etalon
    left join folder_diff fd on fd.folder_id = etalon.folder_id
    left join folder_diff_server fds on fds.folder_diff_id = fd.id
) cmp
group by server_id, project_id, name
) smry
join project_folder_count on project_folder_count.project_id = smry.project_id
join server s on smry.server_id = s.id and s.enabled
order by region, country, score, hostname, project;
END_SQL
    my $prep = $dbh->prepare($sql);
    if ($project && $region) {
        $prep->execute($project, $project, $region);
    } elsif ($project) {
        $prep->execute($project);
    } elsif ($region) {
        $prep->execute($region);
    } else {
        $prep->execute;
    }
    my $server_arrayref = $dbh->selectall_arrayref($prep, { Slice => {} });
    return $server_arrayref;
}

sub check_sync {
    my ($self, $h) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = 'select * from server where id = ?';
    my $exist = $dbh->selectrow_hashref($sql, undef, $h->{id});

    unless ($exist) {
        $sql = 'insert into server(id, hostname, urldir, enabled, region, country, score, lat, lng) select ?, ?, ?, ?, ?, ?, ?, ?, ?';
        $dbh->prepare($sql)->execute($h->{id}, $h->{hostname}, $h->{urldir}, $h->{enabled}, $h->{region}, $h->{country}, $h->{score}, $h->{lat}, $h->{lng});
        return 2;
    }

    return 0 if $exist->{hostname} ne $h->{hostname};

    my $eq = 1;
    for my $key (qw(urldir enabled region country score lat lng)) {
        next if ($exist->{$key} // '') eq ($h->{$key} // '');
        $eq = 0;
        last;
    }
    return 1 if $eq;
    $sql = 'update server set urldir = ?, enabled = ?, region = ?, country = ?, score = ?, lat = ?, lng = ? where id = ? and hostname = ?';
    $dbh->prepare($sql)->execute($h->{urldir}, $h->{enabled}, $h->{region}, $h->{country}, $h->{score}, $h->{lat}, $h->{lng}, $h->{id}, $h->{hostname});
    return 3;
}

1;
