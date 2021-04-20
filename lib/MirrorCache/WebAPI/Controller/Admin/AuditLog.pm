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


package MirrorCache::WebAPI::Controller::Admin::AuditLog;
use Mojo::Base 'Mojolicious::Controller';

use Time::Piece;
use Time::Seconds;
use Time::ParseDate;

sub index {
    my ($self) = @_;
    if ($self->param('event_id')) {
        $self->stash('search', 'id:' . $self->param('event_id'));
    } if ($self->param('user_id')) {
        $self->stash('search', 'user_id:' . $self->param('user_id'));
    } else {
        $self->stash('search', $self->param('search'));
    }
    $self->render('app/audit_log/index');
}

sub _add_single_query {
    my ($query, $key, $search_terms) = @_;

    return unless @$search_terms;
    my $search = join(' ', @$search_terms);
    @$search_terms = ();

    my %key_mapping = (
        owner => 'owner.nickname',
        user  => 'owner.nickname',
        data  => 'event_data',
        event => 'name',
    );
    if (my $actual_key = $key_mapping{$key}) {
        push(@{$query->{$actual_key}}, ($actual_key => {-like => '%' . $search . '%'}));
    }
    elsif ($key eq 'id' || $key eq 'user_id' || $key eq 'tag') {
        push(@{$query->{$key}}, (('me.' . $key) => {'=' => int($search)}));
    }
    elsif ($key eq 'older' || $key eq 'newer') {
        if ($search eq 'today') {
            $search = '1 day ago';
        }
        elsif ($search eq 'yesterday') {
            $search = '2 days ago';
        }
        else {
            $search = '1 ' . $search unless $search =~ /^[\s\d]/;
            $search .= ' ago'        unless $search =~ /\sago\s*$/;
        }
        if (my $time = parsedate($search, PREFER_PAST => 1, DATE_REQUIRED => 1)) {
            my $time_conditions = ($query->{'me.dt'} //= {-and => []});
            push(
                @{$time_conditions->{-and}},
                { 'me.dt' => {($key eq 'newer' ? '>=' : '<') => localtime($time)->ymd()} }
            );
        }
    }
}

sub _get_search_query {
    my ($raw_search) = @_;

    # construct query only from allowed columns
    my $query       = {};
    my @subsearch   = split(/ /, $raw_search);
    my $current_key = 'data';
    my @current_search;
    for my $s (@subsearch) {
        if (CORE::index($s, ':') == -1) {
            # bareword - add to current_search
            push(@current_search, $s);
        }
        else {
            # start new search group, push the current to the query and reset it
            _add_single_query($query, $current_key, \@current_search);

            my ($key, $search_term) = split(/:/, $s);
            # found new search column, assign key as current key
            $current_key = $key;
            push(@current_search, $search_term);
        }
    }
    # add last single query if anything is entered
    _add_single_query($query, $current_key, \@current_search);

    # add -and => -or structure to constructed query
    my @filter_conds;
    for my $k (keys %$query) {
        push(@filter_conds, (-or => $query->{$k}));
    }
    return \@filter_conds;
}

sub _prepare_data {
    my ($results) = @_;
    my @events;
    while (my $event = $results->next) {
        my $event_owner;
        if ($event->user_id == -1) {
            $event_owner = 'system';
        } else {
            $event_owner = $event->owner ? $event->owner->nickname : 'deleted user';
        }
        push(
            @events,
            {
                id         => $event->id,
                event_time => $event->dt,
                user       => $event_owner,
                user_id    => $event->user_id,
                event      => $event->name,
                tag        => $event->tag,
                event_data => $event->event_data,
            });
    }
    return \@events;
}

sub _render_response {
    my (%args) = @_;
    my $controller       = $args{controller};
    my $resultset_name   = $args{resultset};
    my $order_by_columns = $args{order_by_columns};
    my $filter_conds     = $args{filter_conds};
    my $query_params     = $args{query_params} // {};

    # determine total count
    my $resultset   = $controller->schema->resultset($resultset_name);
    my $total_count = $resultset->count;

    # determine filtered count
    my $filtered_count;
    if ($filter_conds) {
        $filtered_count = $resultset->search({-and => $filter_conds}, $query_params)->count;
    }
    else {
        $filter_conds   = [];
        $filtered_count = $total_count;
    }

    # add parameter for sort order
    my @order_by_params;
    my $index = 0;
    while (1) {
        my $column_index = $controller->param("order[$index][column]") // @$order_by_columns;
        my $column_order = $controller->param("order[$index][dir]") // '';
        last unless $column_index < @$order_by_columns && grep { $column_order eq $_ } qw(asc desc);
        push(@order_by_params, {'-' . $column_order => $order_by_columns->[$column_index]});
        ++$index;
    }
    $query_params->{order_by} = \@order_by_params if @order_by_params;

    # add parameter for paging
    my $first_row = $controller->param('start');
    $query_params->{offset} = $first_row if $first_row;
    my $row_limit = $controller->param('length');
    $query_params->{rows} = $row_limit if $row_limit;

    # get results and compute data for JSON serialization
    my $results = $resultset->search({-and => $filter_conds}, $query_params);
    my $data    = _prepare_data($results);

    $controller->render(
        json => {
            recordsTotal    => $total_count,
            recordsFiltered => $filtered_count,
            data            => $data,
        });
}

sub ajax {
    my ($self) = @_;

    _render_response(
        controller       => $self,
        resultset        => 'AuditEvent',
        order_by_columns => [qw(dt owner.nickname name event_data)],
        filter_conds     => _get_search_query($self->param('search[value]') // ''),
        query_params     => { prefetch => 'owner', cache => 1 },
    );
}

1;
