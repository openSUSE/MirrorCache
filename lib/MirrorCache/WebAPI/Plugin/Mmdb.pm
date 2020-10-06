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

use MaxMind::DB::Reader;

my $reader;

sub register {
    (my $self, my $app, $reader) = @_;
    
    $app->helper( 'mmdb.country' => sub {
        my ($c, $ip) = @_;
        $ip = shift->client_ip unless $ip; 
        my $record = $reader->record_for_address($ip);
        return $record->{country}->{iso_code} if $record;
        return undef;
    });

    $app->helper( 'mmdb.emit_miss' => sub {
        my ($c, $path) = @_;
        my $ip = $c->client_ip;
        my $country = $c->mmdb->country($ip);
        if ($country) {
            $c->emit_event('mc_path_miss', { path => $path, country => $country } );
        } else {
            $c->emit_event('mc_unknown_ip', $ip);
        }
    });
}

1;
