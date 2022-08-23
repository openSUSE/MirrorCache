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

    my $mirrors = $schema->resultset('Server')->report_mirrors;
    # this is just tmp structure we use for aggregation
    my %report;
    my %sponsor;
    for my $m (@$mirrors) {
        $report{$m->{region}}{$m->{country}}{$m->{url}}{$m->{project}} = [$m->{score},$m->{victim}];
        $sponsor{$m->{url}} = [$m->{sponsor},$m->{sponsor_url}];
    }
    # json expects array, so we collect array here
    my @report;
    for my $region (sort keys %report) {
        my $by_region = $report{$region};
        for my $country (sort keys %$by_region) {
            my $by_country = $by_region->{$country};
            for my $url (sort keys %$by_country) {
                my %row = (
                    region  => $region,
                    country => $country,
                    url     => $url,
                );
                if (my $sponsor = $sponsor{$url}) {
                    $row{'sponsor'} = $sponsor->[0] if $sponsor->[0];
                    $row{'sponsor_url'} = $sponsor->[1] if $sponsor->[1];
                }
                
                my $by_project = $by_country->{$url};
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
                push @report, \%row;
            }
        }
    }

    my @regions = $app->subsidiary->regions;
    for my $region (@regions) {
        next unless $region;
        next if $app->subsidiary->local($region);
        my $url = $app->subsidiary->url($region);
        eval {
            my $res = Mojo::UserAgent->new->get($url . "/rest/repmirror")->res;
            if ($res->code < 300 && $res->code > 199) {
                my $json = $res->json('/report');
                my @elements = $json->@*;
                for my $item (@elements) {
                    $item->{region} = $item->{region} . " ($url)";
                }
                push @report, @elements if @elements;
            } else {
                print STDERR "Error code accessing {$url}:" . $res->code . "\n";
            }
            1;
        } or print STDERR "Error requesting {$url}:" . $@ . "\n";
    }
    my $json = encode_json(\@report);
    my $sql = 'insert into report_body select 1, now(), ?';

    $schema->storage->dbh->prepare($sql)->execute($json);

    return $job->finish if $once;
    return $job->retry({delay => $DELAY});
}

1;
