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

package MirrorCache::WebAPI::Controller::Rest::Table;
use Mojo::Base 'Mojolicious::Controller';

use Mojo::Util 'trim';
use Try::Tiny;

use Data::Dumper;

my %tables = (
    Server => {
        keys     => [['id'], ['hostname'],],
        cols     => ['id', 'hostname', 'urldir', 'enabled', 'region', 'country', 'comment', 'public notes'],
        required => ['id', 'hostname', 'urldir'],
        defaults => {urldir => '/'},
    },
    Folder => {
        keys     => [['id'], ['path'],],
        cols     => ['id', 'path', 'db sync last', 'db sync scheduled', 'db sync priority'],
    },
);

sub list {
    my ($self) = @_;

    my $table = $self->param("table");
    my %search;

    for my $key (@{$tables{$table}->{keys}}) {
        my $have = 1;
        for my $par (@$key) {
            $have &&= $self->param($par);
        }
        if ($have) {
            for my $par (@$key) {
                $search{$par} = $self->param($par);
            }
        }
    }

    my @result;
    eval {
        my $rs = $self->schema->resultset($table);
        @result = %search ? $rs->search(\%search) : $rs->all;
    };
    my $error = $@;
    if ($error) {
        return $self->render(json => {error => $error}, status => 404);
    }

    $self->render(
        json => {
            $table => [
                map {
                    my $row      = $_;
                    my %hash     = (
                        (
                            map {
                                my $col = $_;
                                my $col1 = $col;
                                $col1 =~ tr/ /_/;
                                my $val = $row->get_column($col1);
                                $val ? ($col => $val) : ()
                            } @{$tables{$table}->{cols}}
                        ));
                    \%hash;
                } @result
            ]});
}

sub create {
    my ($self) = @_;

    return $self->render(json => {error => 'Could not identify current user (you).'}, status => 400) unless $self->current_user;

    my $table  = $self->param("table");
    
    my %entry  = %{$tables{$table}->{defaults}};
    my $prepare_error = $self->_prepare_params($table, \%entry);
    return $self->render(json => {error => $prepare_error}, status => 400) if defined $prepare_error;

    my $error;
    my $id;

    try { $id = $self->schema->resultset($table)->create(\%entry)->id; } catch { $error = shift; };

    if ($error) {
        return $self->render(json => {error => $error}, status => 400);
    }
    my %event_data;
    for my $k (keys %entry) {
        next if !$entry{$k} or "$entry{$k}" eq '';
        $event_data{$k} = $entry{$k};
    }
    my $name = 'mc_' . lc $table . '_create';
    $self->emit_event($name, \%event_data, $self->current_user->id);
    $self->render(json => {id => $id});
}

sub update {
    my ($self) = @_;

    return $self->render(json => {error => 'Could not identify current user (you).'}, status => 400) unless $self->current_user;

    my $table = $self->param("table");

    my $entry = {};
    my $prepare_error = $self->_prepare_params($table, $entry);
    return $self->render(json => {error => $prepare_error}, status => 400) if defined $prepare_error;

    my $schema = $self->schema;

    my $error;
    my $ret;
    my $update = sub {
        my $rc = $schema->resultset($table)->find({id => $self->param('id')});
        if ($rc) {
            my @event_data;
            for my $k (keys %{ $entry }) {
                next if !$entry->{$k} || "$entry->{$k}" eq '' and !$rc->$k || $rc->$k . '' eq '';
                if (!$rc->$k or $rc->$k . '' eq '') {
                    push @event_data, {"new $k" => $entry->{$k}};
                } elsif ($entry->{$k} ne $rc->$k) {
                    push @event_data, {"new $k" => $entry->{$k}, "old $k" => $rc->$k . ''};
                } else {
                    push @event_data, {$k => $entry->{$k}};
                }
            }
            my $name = 'mc_' . lc $table . '_update';
            $self->emit_event($name, \@event_data, $self->current_user->id);
            $rc->update($entry);
            $ret = 1;
        }
        else {
            $ret = 0;
        }
    };

    try {
        $schema->txn_do($update);
    }
    catch {
        # The first line of the backtrace gives us the error message we want
        $error = (split /\n/, $_)[0];
    };

    if ($ret && $ret == 0) {
        return $self->render(json => {error => 'Not found'}, status => 404);
    }
    if (!$ret) {
        return $self->render(json => {error => $error}, status => 400);
    }
    $self->render(json => {result => int($ret)});
}

=over 4

=item destroy()

Deletes a table record given its type (server, folder) and its id. Returns
a 404 error code when the table is not found, 400 on other errors.

=back

=cut

sub destroy {
    my ($self) = @_;

    return $self->render(json => {error => 'Could not identify current user (you).'}, status => 400) unless $self->current_user;

    my $table    = $self->param("table");
    my $schema   = $self->schema;
    my $ret;
    my $error;
    my $res;

    try {
        my $rs = $schema->resultset($table);
        $res = $rs->find({id => $self->param('id')});
        if ($res) {
            my %event_data;
            for my $k (@{$tables{$table}->{cols}}) {
                $k =~ tr/ /_/;
                next if !$res->$k or $res->$k . '' eq '';
                $event_data{$k} = $res->$k;
            }
            my $name = 'mc_' . lc $table . '_delete';
            $self->emit_event($name, \%event_data, $self->current_user->id);
            $ret = $res->delete;
        }
        else {
            $ret = 0;
        }
    }
    catch {
        # The first line of the backtrace gives us the error message we want
        $error = (split /\n/, $_)[0];
    };

    if ($ret && $ret == 0) {
        return $self->render(json => {error => 'Not found'}, status => 404);
    }
    if (!$ret) {
        return $self->render(json => {error => $error}, status => 400);
    }
    $self->render(json => {result => int($ret)});
}

=over 4

=item _prepare_params()

Internal method to validate and prepare parameters for adding or updating an admin table.
Used by both B<create()> and B<update()> methods.

=back

=cut

sub _prepare_params {
    my ($self, $table, $entry) = @_;
    my $validation = $self->validation;

    for my $par (@{$tables{$table}->{required}}) {
        $validation->required($par);
    }
    for my $par (@{$tables{$table}->{cols}}) {
        next if $par eq 'id' && !$self->param($par);
        if (defined $validation->param($par)) {
            $entry->{$par} = trim $validation->param($par);
        } else {
            my $par1 = $par;
            $par1 =~ tr/ /_/;
            $entry->{$par1} = $self->param($par);
        }
    }

    if ($validation->has_error) {
        return "Missing parameter: " . join(', ', @{$validation->failed});
    }
    return undef;
}

1;
