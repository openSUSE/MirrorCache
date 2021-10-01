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
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

package MirrorCache::WebAPI::Plugin::Geolocation;
use Mojo::Base 'Mojolicious::Plugin';
use MirrorCache::Utils 'region_for_country';

my $geodb;

sub register {
    my ($self, $app, $conf) = @_;
    $geodb = $conf->{geodb} if $conf;

    $app->helper( 'geodb.country_and_region' => sub {
        my ($c, $ip) = @_;
        return ("", "") unless $geodb;
        $ip = shift->client_ip unless $ip;
        return ('us','na') if $ip eq '::1' || $ip eq '::ffff:127.0.0.1'; # for testing only

        $ip =~ s/^::ffff://;
        my $country = _get_country($geodb, $ip) // '';
        my $region  = region_for_country($country) // '';

        return ($country, $region);
    });

    $app->helper( 'geodb.location' => sub {
        my ($c, $ip) = @_;
        return "" unless $geodb;
        $ip = shift->client_ip unless $ip;
        return (0,0,'us','na') if $ip eq '::1' || $ip eq '::ffff:127.0.0.1'; # for testing only

        $ip =~ s/^::ffff://;
        my $country = _get_country($geodb, $ip) // '';
        my $region  = region_for_country($country) // '';

        my $latitude = $geodb->get_latitude($ip);
        $latitude = undef unless int($latitude);

        my $longitude = $geodb->get_longitude($ip);
        $longitude = undef unless int($longitude);

        return ($latitude,$longitude,$country,$region);
    });

    if ($geodb) {
        $app->plugin('ClientIP', private => [qw(127.0.0.0/8 192.168.0.0/16)]);
        $app->helper( 'geodb.client_ip' => sub { return shift->client_ip; } );
    } else {
        $app->helper( 'geodb.client_ip' => sub { return shift->tx->remote_address; } );
    }
}

sub _get_country {
  my ($geodb, $ip) = @_;

  my $country = $geodb->get_country_short($ip);
  return '' if $country eq '-';
  return lc($country);
}


1;
