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
            prev => { 
                prev_minute_hit  => $prevminuteref->{hit},
                prev_minute_miss => $prevminuteref->{miss},
                prev_hour_hit    => $prevhourref->{hit},
                prev_hour_miss   => $prevhourref->{miss},
                prev_day_hit     => $prevdayref->{hit},
                prev_day_miss    => $prevdayref->{miss},
            },
            curr => {
                curr_minute_hit  => $currref->{minute}->{hit},
                curr_minute_miss => $currref->{minute}->{miss},
                curr_hour_hit    => $currref->{hour}->{hit},
                curr_hour_miss   => $currref->{hour}->{miss},
                curr_day_hit     => $currref->{day}->{hit},
                curr_day_miss    => $currref->{day}->{miss},
            },
        }
    );
}

1;
