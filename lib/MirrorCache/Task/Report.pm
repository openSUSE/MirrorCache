# Copyright (C) 2022 SUSE LLC
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

package MirrorCache::Task::Report;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::UserAgent;
use Mojo::JSON qw(decode_json encode_json);

sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(report => sub { _run($app, @_) });
}

my $DELAY = int($ENV{MIRRORCACHE_SCHEDULE_REPORT_RETRY_INTERVAL} // 15 * 60);

sub _run {
    my ($app, $job, $once) = @_;
    my $minion = $app->minion;
    return $job->finish('Previous report job is still active')
      unless my $guard = $minion->guard('report', 15*60);

    my $schema = $app->schema;
    _run_mirrors($app, $schema);
    _run_download_hour($app, $schema);
    _run_download_day($app, $schema);

    return $job->finish if $once;
    return $job->retry({delay => $DELAY});
}

sub _run_download_day {
    my ($app, $schema) = @_;
    my $sql = "
insert into agg_download(period, dt, project_id, country, mirror_id,
        file_type,
        os_id, os_version,
        arch_id,
        meta_id,
        cnt,
        cnt_known,
        bytes)
select 'day'::stat_period_t, date_trunc('day', dt), project_id, country, mirror_id,
        file_type,
        os_id, os_version,
        arch_id,
        meta_id,
        sum(cnt),
        sum(cnt_known),
        sum(bytes)
from agg_download
where period = 'hour'
  and dt >= coalesce((select max(dt) + interval '1 day' from agg_download where period = 'day'), now() - interval '10 day')
  and dt < date_trunc('day', now())
group by date_trunc('day', dt), project_id, country, mirror_id,
        file_type,
        os_id, os_version,
        arch_id,
        meta_id
";

    unless ($schema->pg) {
        $sql =~ s/::stat_period_t//g;
        $sql =~ s/interval '1 day'/interval 1 day/g;
        $sql =~ s/interval '10 day'/interval 10 day/g;
        $sql =~ s/date_trunc\('day', /date(/g;
    }

    $schema->storage->dbh->prepare($sql)->execute();
    1;
}

sub _run_download_hour {
    my ($app, $schema) = @_;
    my $sql = "
insert into agg_download(period, dt, project_id, country, mirror_id,
        file_type,
        os_id, os_version,
        arch_id,
        meta_id,
        cnt,
        cnt_known,
        bytes)
select 'hour'::stat_period_t cperiod, date_trunc('hour', stat.dt) cdt, coalesce(p.id, 0) cpid, coalesce(stat.country, '') ccountry, stat.mirror_id cmirror_id,
        coalesce(ft.id, 0) cft_id,
        coalesce(os.id, 0) cos_id, coalesce(regexp_replace(stat.path, os.mask, os.version), '') cos_version,
        coalesce(arch.id, 0) carch_id,
        0 cmeta_id,
        count(*) cnt,
        sum(case when file_id > 0 then 1 else 0 end) cnt_known,
        sum(coalesce(f.size, 0)) bytes
from
stat
left join project p            on stat.path like concat(p.path, '%')
left join file f               on f.id = file_id
left join popular_file_type ft on stat.path like concat('%.', ft.name)
left join popular_os os        on stat.path ~ os.mask   and (coalesce(os.neg_mask,'') = '' or not stat.path ~ os.neg_mask)
left join popular_arch arch    on stat.path like concat('%', arch.name, '%')
left join agg_download d       on stat.mirror_id = d.mirror_id
                              and coalesce(stat.country,'') = d.country
                              and d.project_id = coalesce(p.id, 0)
                              and d.file_type  = coalesce(ft.id, 0)
                              and d.os_id = coalesce(os.id, 0)
                              and d.os_version = coalesce(regexp_replace(stat.path, os.mask, os.version), '')
                              and d.arch_id = coalesce(arch.id, 0)
                              and d.dt = date_trunc('hour', stat.dt)
                              and d.dt > now() - interval '7 hour'
                              and d.period = 'hour'
where stat.dt > now() - interval '6 hour'
    and stat.dt < date_trunc('hour', now())
    and stat.mirror_id > -2
    and d.period IS NULL
group by cperiod, cdt, cpid, ccountry, cmirror_id, cft_id, cos_id, cos_version, carch_id, cmeta_id
";

    unless ($schema->pg) {
        $sql =~ s/::stat_period_t//g;
        $sql =~ s/interval '6 hour'/interval 6 hour/g;
        $sql =~ s/interval '7 hour'/interval 7 hour/g;
        $sql =~
s/date_trunc\('hour', stat.dt\)/(date(stat.dt) + interval hour(stat.dt) hour)/g;
        $sql =~
s/date_trunc\('hour', now\(\)\)/(date(now()) + interval hour(now()) hour)/g;
        $sql =~ s/ ~ / RLIKE /g;
    }

    $schema->storage->dbh->prepare($sql)->execute();
    1;
}

sub _run_mirrors {
    my ($app, $schema) = @_;

    my $mirrors = $schema->resultset('Server')->report_mirrors;

    # this is just tmp structure we use for aggregation
    my %report;
    my %sponsor;
    my %capability;
    my %url;
    for my $m (@$mirrors) {
        $report{ $m->{region} }{ $m->{country} }{ $m->{hostname} }{ $m->{project} }
          = [ $m->{score}, $m->{victim} ];
        $sponsor{$m->{hostname}} = [$m->{sponsor},$m->{sponsor_url}];
        $url{$m->{hostname}} = $m->{url};
        for my $capability (qw/http https ipv4 ipv6 ftp rsync/) {
            $capability{$m->{hostname}}{$capability} = $m->{$capability . '_url'} if $m->{$capability . '_url'};
        }
    }

    # json expects array, so we collect array here
    my @report;
    for my $region (sort keys %report) {
        my $by_region = $report{$region};
        for my $country (sort keys %$by_region) {
            my $by_country = $by_region->{$country};
            for my $hostname (sort keys %$by_country) {
                my %row = (
                    region   => $region,
                    country  => $country,
                    hostname => $hostname,
                    url      => $url{$hostname},
                );
                if (my $sponsor = $sponsor{$hostname}) {
                    $row{'sponsor'} = $sponsor->[0] if $sponsor->[0];
                    $row{'sponsor_url'} = $sponsor->[1] if $sponsor->[1];
                }

                my $by_project = $by_country->{$hostname};
                for my $project (sort keys %$by_project) {
                    my $p = $by_project->{$project};
                    my $score = $p->[0];
                    my $victim = $p->[1];
                    $project =~ tr/ //ds;
                    $project =~ tr/\.//ds;
                    $project = lc($project);
                    $project = "c$project" if $project =~ /^\d/;
                    $row{$project . 'score'}  = $score;
                    $row{$project . 'victim'} = $victim;
                }
                # add capabilities
                for my $capability (qw/http https ipv4 ipv6 ftp rsync/) {
                    if (my $capability_url = $capability{$hostname}{$capability}) {
                        $row{$capability . '_url'} = $capability_url;
                    }
                }
                push @report, \%row;
            }
        }
    }

    my @regions = $app->subsidiary->regions;
    my %regions_res;
    my $must_use_tag = 0;
    for my $region (@regions) {
        next unless $region;
        next if $app->subsidiary->is_local($region);
        $must_use_tag = 1;
        my $url = $app->subsidiary->url($region);
        eval {
            my $res =
              Mojo::UserAgent->new->get( $url . "/rest/repmirror" )->res;
            if (!$res->code) {
                print STDERR "Error accessing {$url}:\n";
            }
            elsif ( $res->code < 300 && $res->code > 199 ) {
                $regions_res{$region} = $res->json;
            }
            else {
                print STDERR "Error code accessing {$url}:" . $res->code . "\n";
            }
            1;
        } or print STDERR "Error requesting {$url}:" . $@ . "\n";
    }
    my $json = encode_json(\@report);
    unless ($must_use_tag) {
        my $sql =
          'insert into report_body(report_id, dt, body) select 1, now(), ?';
        $schema->storage->dbh->prepare($sql)->execute($json);
        return;
    }

    my $sql = 'insert into report_body(report_id, dt, body, tag) select 1, now(), ?, ?';
    $schema->storage->dbh->prepare($sql)->execute($json, 'local');
    for my $region (@regions) {
        next unless $region;
        next if $app->subsidiary->is_local($region);
        my $res = $regions_res{$region};
        next unless $res;
        $json = encode_json($res);
        next unless $json;
        $schema->storage->dbh->prepare($sql)->execute($json, $region);
    }
}

1;
