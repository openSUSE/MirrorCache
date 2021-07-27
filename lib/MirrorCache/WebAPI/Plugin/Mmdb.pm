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
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

package MirrorCache::WebAPI::Plugin::Mmdb;
use Mojo::Base 'Mojolicious::Plugin';


my $reader;

sub register {
    my ($self, $app, $conf) = @_;
    $reader = $conf->{reader} if $conf;

    $app->helper( 'mmdb.country' => sub {
        my ($c, $ip) = @_;
        return "" unless $reader;
        $ip = shift->client_ip unless $ip;
        return 'us' if $ip eq '::1' || $ip eq '::ffff:127.0.0.1'; # for testing only
        my $record = $reader->record_for_address($ip);
        return $record->{country}->{iso_code} if $record;
        return undef;
    });

    $app->helper( 'mmdb.region' => sub {
        my ($c, $ip) = @_;
        return ("", "") unless $reader;
        $ip = shift->client_ip unless $ip;
        return ('us','na') if $ip eq '::1' || $ip eq '::ffff:127.0.0.1'; # for testing only
        my $record = $reader->record_for_address($ip);
        my ($region, $country) = ("","");
        eval {
            $region  = $record->{continent}->{code};
            $country = $record->{country}->{iso_code};
        } if $record;
        return ($region, $country);
    });

    $app->helper( 'mmdb.location' => sub {
        my ($c, $ip) = @_;
        return "" unless $reader;
        $ip = shift->client_ip unless $ip;
        return (0,0,'us','na') if $ip eq '::1' || $ip eq '::ffff:127.0.0.1'; # for testing only
        my $record = $reader->record_for_address($ip);
        return ($record->{location}->{latitude},$record->{location}->{longitude},lc($record->{country}->{iso_code}),lc($record->{continent}->{code})) if $record;
        return undef;
    });

    if ($reader) {
        $app->plugin('ClientIP', private => [qw(127.0.0.0/8 192.168.0.0/16)]);
        $app->helper( 'mmdb.client_ip' => sub { return shift->client_ip; } );
    } else {
        $app->helper( 'mmdb.client_ip' => sub { return shift->tx->remote_address; } );
    }
}

1;
