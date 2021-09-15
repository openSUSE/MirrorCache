# Copyright (C) 2021 SUSE LLC
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

package MirrorCache::Task::MirrorLocation;
use Mojo::Base 'Mojolicious::Plugin';

use Net::URIProtocols qw/ProbeHttp ProbeHttps ProbeIpv4 ProbeIpv6/;
use Net::Nslookup6 qw/nslookup/;
use URI;
use Socket;

sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(mirror_location       => sub { _location($app, @_) });
}

sub _location {
    my ($app, $job, $server_id) = @_;
    return $job->fail('Empty parameter is not allowed') unless $server_id;

    my $minion = $app->minion;

    my $schema = $app->schema;
    my $rs = $schema->resultset('Server');
    my $s = $rs->find({ id => $server_id });
    return $job->fail("Couldn't find server") unless $s;
    my $hostname = $s->hostname;
    return $job->fail("Empty hostname") unless $hostname;

    $hostname = 'http://' . $hostname if -1 == index($hostname, '://');
    my $uri = URI->new($hostname)->canonical;
    my $ip = $uri->host;
    $ip = nslookup($ip) unless _isValidIP($ip);
    my ($lat, $lng, $country, $continent) = $app->geodb->location($ip);
    $lat = sprintf("%.3f", $lat) if $lat;
    $lng = sprintf("%.3f", $lng) if $lng;
    return $job->fail("Couldn't identify location") unless ($lat || $lng) && $country && $continent;
    return $job->fail("Country doesn't match, expected: " . $s->country . '; got: ' . $country) if $s->country && $country ne $s->country;

    my ($old_region, $old_lat, $old_lng) = (($s->region // ''), ($s->lat // ''), ($s->lng // ''));
    return $job->finish("No changes detected") if $lat eq $old_lat && $lng eq $old_lng && $continent eq $old_region;

    $s->update({ lat => $lat, lng => $lng, region => $continent });

    return $job->finish("Updated to ($continent,$lat,$lng) from ($old_region,$old_lat,$old_lng)");
}

# check whether $hostname is actually IP address
sub _isValidIP
{
    return $_[0] =~ /^[\d\.]*$/ && inet_aton($_[0]);
}

1;
