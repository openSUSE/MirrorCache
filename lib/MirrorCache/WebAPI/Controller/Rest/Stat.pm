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
use Data::Dumper;

sub list {
    my ($self) = @_;

    my $tx = $self->render_later->tx;
    my ($prevminuteref, $prevhourref, $prevdayref, $curr);

    my $rendered;
    my $handle_error = sub {
        return if $rendered;
        $rendered = 1;
        my @reason = @_;
        my $reason = scalar(@reason)? Dumper(@reason) : 'unknown';
        $self->render(json => {error => $reason}, status => 500) ;
    };

    my $p = Mojo::Promise->new->timeout(5);
    my $rs = $self->schema->resultset('Stat');
    $p->then(sub {
        $prevdayref = $rs->prev_day;
    })->catch($handle_error)->then(sub {
        $prevhourref = $rs->prev_hour;
    })->catch($handle_error)->then(sub {
        $prevminuteref = $rs->prev_minute;
    })->catch($handle_error)->then(sub {
        $curr = $rs->curr;
    })->catch($handle_error)->then(sub {
        my %res = ();
        my $fill = sub {
            my ($prev, $period) = @_;
            my %h = (
                hit       => _toint($curr->{"hit_$period"}),
                miss      => _toint($curr->{"miss_$period"}),
                prev_hit  => _toint($prev->{hit}),
                prev_miss => _toint($prev->{miss}),
            );
            # geo redirects are not always enabled, so show them only if exist
            if (my $x = _toint($prev->{geo})) {
                $h{'prev_geo'} = $x;
            }
            if (my $x = _toint($prev->{bot})) {
                $h{'prev_bot'} = $x;
            }
            if (my $x = _toint($curr->{"geo_$period"})) {
                $h{'geo'} = $x;
            }
            if (my $y = _toint($curr->{"bot_$period"})) {
                $h{'bot'} = $y;
            }
            $res{$period} = \%h;
        };

        $fill->($prevminuteref, 'minute');
        $fill->($prevhourref, 'hour');
        $fill->($prevdayref, 'day');
        $self->render(json => \%res);
    })->catch($handle_error);

    $p->resolve;
}

sub mylist {
    my $self = shift;
    my $dm = MirrorCache::Datamodule->new->app($self->app);
    $dm->reset($self);
    my $ip      = $dm->ip;
    my $ip_sha1 = $dm->ip_sha1;
    my $tx = $self->render_later->tx;
    my $curr;

    my $rendered;
    my $handle_error = sub {
        return if $rendered;
        $rendered = 1;
        my @reason = @_;
        my $reason = scalar(@reason)? Dumper(@reason) : 'unknown';
        $self->render(json => {error => $reason}, status => 500) ;
    };

    my $p = Mojo::Promise->new->timeout(5);
    my $rs = $self->schema->resultset('Stat');
    my %res = (
        ip => $ip,
        ip_sha1 => $ip_sha1,
    );
    $p->then(sub {
        $curr = $rs->mycurr($ip_sha1);
    })->catch($handle_error)->then(sub {
        my $fill = sub {
            my ($period) = @_;
            my %h = (
                hit  => _toint($curr->{"hit_$period"}),
                miss => _toint($curr->{"miss_$period"}),
            );
            if (my $x = _toint($curr->{"geo_$period"})) {
                $h{'geo'} = $x;
            }
            if (my $y = _toint($curr->{"bot_$period"})) {
                $h{'bot'} = $y;
            }
            $res{$period} = \%h;
        };
        $fill->('minute');
        $fill->('hour');
        $fill->('day');
        $self->render(json => \%res);
    })->catch($handle_error);

    $p->resolve;
}

sub _toint {
    my $n = shift;
    return 0 unless $n;
    return $n + 0;
}

1;
