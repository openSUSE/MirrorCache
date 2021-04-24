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
                    my @settings; # = sort { $a->key cmp $b->key } $row->settings;
                    my %hash     = (
                        (
                            map {
                                my $col = $_;
                                my $col1 = $col;
                                $col1 =~ tr/ /_/;
                                my $val = $row->get_column($col1);
                                $val ? ($col => $val) : ()
                            } @{$tables{$table}->{cols}}
                        ),
                        settings => [map { {key => $_->key, value => $_->value} } @settings]);
                    \%hash;
                } @result
            ]});
}

sub create {
    my ($self) = @_;
    my $table  = $self->param("table");
    my %entry  = %{$tables{$table}->{defaults}};

    my ($error_message, $settings, $keys) = $self->_prepare_settings($table, \%entry);
    return $self->render(json => {error => $error_message}, status => 400) if defined $error_message;

    # $entry{settings} = $settings;

    my $error;
    my $id;

    try { $id = $self->schema->resultset($table)->create(\%entry)->id; } catch { $error = shift; };

    if ($error) {
        return $self->render(json => {error => $error}, status => 400);
    }
    $self->render(json => {id => $id});
}

sub update {
    my ($self) = @_;
    my $table = $self->param("table");

    my $entry = {};
    my ($error_message, $settings, $keys) = $self->_prepare_settings($table, $entry);

    return $self->render(json => {error => $error_message}, status => 400) if defined $error_message;

    my $schema = $self->schema;

    my $error;
    my $ret;
    my $update = sub {
        my $rc = $schema->resultset($table)->find({id => $self->param('id')});
        if ($rc) {
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

Deletes a table given its type (machine, test suite or product) and its id. Returns
a 404 error code when the table is not found, 400 on other errors or a JSON block
with the number of deleted tables on success.

=back

=cut

sub destroy {
    my ($self) = @_;

    my $table    = $self->param("table");
    my $schema   = $self->schema;
    my $ret;
    my $error;
    my $res;

    try {
        my $rs = $schema->resultset($table);
        $res = $rs->search({id => $self->param('id')});
        $ret = $res->delete;
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

=item _prepare_settings()

Internal method to prepare settings when add or update admin table.
Use by both B<create()> and B<update()> method.

=back

=cut

sub _prepare_settings {
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

    # $entry->{description} = $self->param('description');
    my $hp = $self->hparams();
    my @settings;
    my @keys;
    # if ($hp->{settings}) {
    #    for my $k (keys %{$hp->{settings}}) {
    #        $k = trim $k;
    #        my $value = trim $hp->{settings}->{$k};
    #        push @settings, {key => $k, value => $value};
    #        push @keys, $k;
    #    }
    # }
    return (undef, \@settings, \@keys);
}

1;
