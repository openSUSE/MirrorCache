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
# with this program; if not, see <http://www.gnu.org/licenses/>.

package MirrorCache::Schema::ResultSet::AuditEvent;

use strict;
use warnings;

use Time::Piece;
use Time::Seconds;
use Time::ParseDate;

use base 'DBIx::Class::ResultSet';
use Mojo::JSON qw/decode_json/;

sub mirror_path_errors {
    my ($self, $prev_event_log_id, $limit) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = "select id, event_data from audit_event where name='mirror_path_error'";
    $sql = "$sql and id > $prev_event_log_id" if $prev_event_log_id;
    $sql = "$sql union all select max(id), '-max_id' from audit_event";
    $sql = "$sql order by id desc";
    $sql = "$sql limit ($limit+1)" if $limit;

    my $prep = $dbh->prepare($sql);
    $prep->execute();
    my $arrayref = $dbh->selectall_arrayref($prep, { Slice => {} });
    my $id;
    my %path_country = ();
    my %countries = ();
    my %seen  = ();
    foreach my $miss ( @$arrayref ) {
        my $event_data = $miss->{event_data};
        next if $seen{$event_data};
        $id = $miss->{id} unless $id;
        next if $event_data eq '-max_id';
        $seen{$event_data} = 1;
        my $data = decode_json($event_data);
        my $path = $data->{path};
        next unless $path;
        my $country = $data->{country};
        my $rec = $path_country{$path};
        $rec = {} unless $rec;
        if ($country) {
            $rec->{$country} = 1;
            $countries{$country} = 1 ;
        }
        $path_country{$path} = $rec;
    }
    my @country_list = (keys %countries);
    return ($id, \%path_country, \@country_list);
}

sub cleanup_audit_events {
    my ($self, $app) = @_;

    my $fail_count;
    my $last_warning;

    my $rsource = $self->result_source;
    my $dbh     = $rsource->schema->storage->dbh;

    my @queries;
    my $other_time_constraint;

    my %event_patterns = (
        # system events
        startup => 'startup',
        path    => 'path_%',
        mirror  => 'mirror_%',
        error   => 'error_%',
        # user events from the UI
        user   => 'user_%',
        server => 'server_%',
    );
    # duration in days
    my %storage_durations = (
        # system events
        startup => 14,
        path    => 14,
        mirror  => 14,
        error   => 14,
        # user events from the UI
        user   => 90,
        server => 90,
        # events not defined above
        other => 14,
    );

    for my $event_category (keys %storage_durations) {
        my $duration_in_days = $storage_durations{$event_category};
        next unless $duration_in_days;

        my $time_constraint = parsedate("$duration_in_days days ago", PREFER_PAST => 1, DATE_REQUIRED => 1);
        if (!$time_constraint) {
            $app->log->warn(
                "Ignoring invalid storage duration '$duration_in_days' for audit event type '$event_category'.");
            next;
        }
        $time_constraint = localtime($time_constraint)->ymd;

        if ($event_category eq 'other') {
            $other_time_constraint = $time_constraint;
            next;
        }

        my $event_pattern = $event_patterns{$event_category};
        if (!$event_pattern) {
            $app->log->warn("Ignoring unknown event type '$event_category'.");
            next;
        }
        push(@queries, {name => {-like => $event_pattern}, dt => {'<' => $time_constraint}});
    }

    for my $query (@queries) {
        eval {
            $self->search($query, {order_by => 'dt', rows => 100000})->delete;
            1;
        } or do {
            $fail_count++;
            $last_warning = $@;
            $app->log->warn("Cleanup of audit events failed: $@");
        }
    }

    if ($other_time_constraint) {
        my @pattern_values = values %event_patterns;
        my $sql_other      = 'delete from audit_event where id in (';
        $sql_other = "$sql_other select id from audit_event where dt < ? and";
        $sql_other = "$sql_other " . join(' and ', map { 'name not like ?' } @pattern_values);
        $sql_other = "$sql_other order by dt limit 100000 )";
        eval {
            $dbh->prepare($sql_other)->execute($other_time_constraint, @pattern_values);
            1;
        } or do {
            $fail_count++;
            $last_warning = $@;
            $app->log->warn("Cleanup of audit events failed: $@");
        }
    }
    return ($fail_count, $last_warning) if $fail_count;
}

1;
