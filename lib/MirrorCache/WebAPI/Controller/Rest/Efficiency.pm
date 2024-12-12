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

package MirrorCache::WebAPI::Controller::Rest::Efficiency;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Promise;
use Data::Dumper;

sub list {
    my ($self) = @_;

    my $period = $self->param('period') // 'hour';
    my $limit  = 30;

    my $tx = $self->render_later->tx;

    my $rendered;
    my $handle_error = sub {
        return if $rendered;
        $rendered = 1;
        my @reason = @_;
        my $reason = scalar(@reason)? Dumper(@reason) : 'unknown';
        $self->render(json => {error => $reason}, status => 500) ;
    };

    my $res;
    my $p = Mojo::Promise->new->timeout(5);
    $p->then(sub {
        my $rs = $self->schema->resultset('Stat');
        $res = $rs->select_efficiency($period, $limit);
    })->catch($handle_error)->then(sub {
        $self->render(json => $res);
    })->catch($handle_error);

    $p->resolve;
}

1;
