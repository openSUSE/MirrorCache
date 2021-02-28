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

package MirrorCache::WebAPI::Controller::Rest::Stat;
use Mojo::Base 'Mojolicious::Controller';
use Data::Dumper;

sub list {
    my ($self) = @_;

    my $rs = $self->schema->resultset('Stat');
    my $prevminuteref = $rs->prev_minute;
    my $prevhourref   = $rs->prev_hour;
    my $prevdayref    = $rs->prev_day;

    my $currref = $rs->curr;

    $self->render(
        json => {
            minute => { 
                prev_hit  => _toint($prevminuteref->{hit}),
                prev_miss => _toint($prevminuteref->{miss}),
                hit  => _toint($currref->{minute}->{hit}),
                miss => _toint($currref->{minute}->{miss}),
            },
            hour => {
                prev_hit    => _toint($prevhourref->{hit}),
                prev_miss   => _toint($prevhourref->{miss}),
                hit    => _toint($currref->{hour}->{hit}),
                miss   => _toint($currref->{hour}->{miss}),
            },
            day => {
                prev_hit     => _toint($prevdayref->{hit}),
                prev_miss    => _toint($prevdayref->{miss}),
                hit     => _toint($currref->{day}->{hit}),
                miss    => _toint($currref->{day}->{miss}),
            },
        }
    );
}

sub _toint {
    my $n = shift;
    return 0 unless $n;
    return $n + 0;
}

1;
