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

package MirrorCache::Task::MirrorProbe;
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
    my $href = $rs->search_by_country($country);

    for my $id (sort keys %$href) {
        my $data = $href->{$id};
        for my $capability (SERVER_CAPABILITIES) {
            next unless ($data->{$capability});
            my $success = 1;
            my $error = _probe_capability($data->{'uri'}, $capability);
            $success = 0 if $error;
            $rs->log_probe_outcome($data->{'id'}, $capability, $success, $error);
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
    my ($app, $job, $country) = @_;
    $country = '' unless $country;

    my $minion = $app->minion;
    return $job->finish("Previous projects probe job is still active")
        unless my $guard = $minion->guard('mirror_probe_projects', 600);

    my $schema = $app->schema;
    my $rs = $schema->resultset('Server');
    my $href = $rs->server_projects();

    for my $id (sort keys %$href) {
        my $data = $href->{$id};
        my $oldstate = $data->{state};
        my $success = 1;
        my $code = Mojo::UserAgent->new->head($data->{uri})->result->code;
        $success = 0 if $code ne 200;
        $rs->log_project_probe_outcome($data->{server_id}, $data->{project_id}, $data->{mirror_id}, $success, $code) unless defined $oldstate && $success eq $oldstate;
    }
}

1;
