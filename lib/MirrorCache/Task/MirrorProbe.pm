# Copyright (C) 2020-2025 SUSE LLC
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

package MirrorCache::Task::MirrorProbe;

use POSIX;

use Mojo::Base 'Mojolicious::Plugin';
use Mojo::UserAgent;

use Net::URIProtocols qw/ProbeHttp ProbeHttps ProbeIpv4 ProbeIpv6/;

sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(mirror_probe       => sub { _probe($app, @_) });
    $app->minion->add_task(mirror_force_downs => sub { _force_downs($app, @_) });
    $app->minion->add_task(mirror_force_ups   => sub { _force_ups($app, @_) });

    $app->minion->add_task(mirror_probe_projects => sub { _probe_projects($app, @_) });
}

use constant SERVER_CAPABILITIES => (qw(http https ipv4 ipv6));

sub _probe {
    my ($app, $job, $country) = @_;
    $country = '' unless $country;

    my $minion = $app->minion;
    return $job->finish("Previous mirror probe for {$country} job is still active")
        unless my $guard = $minion->guard('mirror_probe' . $country, 600);

    my $schema = $app->schema;
    my $rs = $schema->resultset('ServerCapabilityDeclaration');
    $rs->adjust_stability();
    my $href = $rs->search_by_country($country);

    my @server_ids = sort keys %$href;
    for my $id (@server_ids) {
        my $data = $href->{$id};
        for my $capability (SERVER_CAPABILITIES) {
            next unless ($data->{$capability});
            $rs->insert_stability_row($id, $capability) unless (defined $data->{"rating_$capability"});

            my $error = _probe_capability($data->{'uri'}, $capability);
            if($error) {
                $rs->reset_stability($data->{'id'}, $capability, $error);
                next;
            }
            my $new_rating = 1000;
            my $ms = $data->{"ms_$capability"};
            # $job->note("$id$capability" => $min);
            if (ceil($ms // 0) > 0) {
                $new_rating = 100 if $ms < 24*60*60*100;
                $new_rating = 10  if $ms < 60*60*100;
            }
            $rs->update_stability($id, $capability, $new_rating) if $new_rating != ($data->{"rating_$capability"} // 0);
        }
    }
    $minion->unlock('mirror_probe_incomplete_for_' . $country);
}

sub _force_downs {
    my ($app, $job) = @_;

    my $minion = $app->minion;
    return $job->finish("Previous job is still active")
        unless my $guard = $minion->guard('mirror_force_downs', 600);

    my $schema = $app->schema;
    my $rs = $schema->resultset('ServerCapabilityDeclaration');
    my $href = $rs->search_all_downs();

    for my $key (sort keys %$href) {
        my $data = $href->{$key};
        my $capability = $data->{capability};
        next unless $capability;
        my $error = _probe_capability($data->{'uri'}, $capability);
        next unless $error;
        $rs->force_down($data->{'id'}, $capability, $error);
    }
}

sub _force_ups {
    my ($app, $job) = @_;

    my $minion = $app->minion;
    return $job->finish("Previous job is still active")
        unless my $guard = $minion->guard('mirror_force_ups', 600);

    my $schema = $app->schema;
    my $rs = $schema->resultset('ServerCapabilityDeclaration');
    my $href = $rs->search_all_forced();

    for my $key (sort keys %$href) {
        my $data = $href->{$key};
        my $capability = $data->{capability};
        next unless $capability;
        my $error = _probe_capability($data->{'uri'}, $capability);
        next if $error;
        $rs->force_up($data->{'id'}, $capability);
    }
}

sub _probe_capability {
    my ($uri, $capability) = @_;

    return ProbeHttp($uri)  if 'http'  eq $capability;
    return ProbeHttps($uri) if 'https' eq $capability;
    return ProbeIpv4($uri)  if 'ipv4'  eq $capability;
    return ProbeIpv6($uri)  if 'ipv6'  eq $capability;
}

sub _probe_projects {
    my ($app, $job, $region) = @_;
    $region = '' unless $region;

    my $minion = $app->minion;
    return $job->finish("Previous projects probe job is still active")
        unless my $guard = $minion->guard('mirror_probe_projects' . $region, 6000);

    my $schema = $app->schema;
    my $rs = $schema->resultset('Server');
    my $href = $rs->server_projects($region);

    my %count;
    my @keys = sort keys %$href;
    $job->note(total => scalar(@keys));

    for my $id (@keys) {
        my $data = $href->{$id};
        my $oldstate = $data->{oldstate};
        my $success = 1;
        my $code = -1;
        eval {
            $code = Mojo::UserAgent->new->max_redirects(5)->head($data->{uri}, {'User-Agent' => 'MirrorCache/probe_projects'})->result->code;
        };
        $success = 0 if ($code < 200 || $code >= 400) and $code != 403;

        $count{$code} = 0 unless $count{$code};
        $count{$code}++;
        $job->note("count$code" => $count{$code});

        $rs->log_project_probe_outcome($data->{server_id}, $data->{project_id}, $data->{mirror_id}, $success, $code) unless defined $oldstate && $success eq $oldstate;
    }
}

1;
