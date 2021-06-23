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
use Mojo::Promise;

sub list {
    my ($self) = @_;

    my $tx = $self->render_later->tx;
    my ($prevminuteref, $prevhourref, $prevdayref, $curr);

    my $p = Mojo::Promise->new->timeout(5);
    $p->then(sub {
        $prevdayref = $self->schema->resultset('Stat')->prev_day;
    })->then(sub {
        $prevhourref = $self->schema->resultset('Stat')->prev_hour;
    })->then(sub {
        $prevminuteref = $self->schema->resultset('Stat')->prev_minute;
    })->then(sub {
        $curr = $self->schema->resultset('Stat')->curr;
    })->then(sub {
        my %res = ();
        my $fill = sub {
            my ($prev, $period) = @_;
            my %h = (
                hit       => _toint($curr->{$period}->{hit}),
                miss      => _toint($curr->{$period}->{miss}),
                prev_hit  => _toint($prev->{hit}),
                prev_miss => _toint($prev->{miss}),
            );
            # geo redirects are not always enabled, so show them only if exist
            if (my $x = _toint($prev->{geo})) {
                $h{'prev_geo'} = $x;
            }
            if (my $x = _toint($curr->{$period}->{geo})) {
                $h{'geo'} = $x;
            }
            $res{$period} = \%h;
        };

        $fill->($prevminuteref, 'minute');
        $fill->($prevhourref, 'hour');
        $fill->($prevdayref, 'day');
        $self->render(json => \%res);
    }, sub {
        my @reason = @_;
        my $reason = scalar(@reason)? Dumper(@reason) : 'unknown';
        $self->render(json => {error => $reason}, status => 500) ;
    });

    $p->resolve;
}

sub _toint {
    my $n = shift;
    return 0 unless $n;
    return $n + 0;
}

1;
