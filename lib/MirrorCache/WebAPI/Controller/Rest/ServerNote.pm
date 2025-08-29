# Copyright (C) 2023 SUSE LLC
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

package MirrorCache::WebAPI::Controller::Rest::ServerNote;
use Mojo::Base 'Mojolicious::Controller';
use Data::Dumper;

sub _has_permission {
    my ($self, $hostname) = @_;
    return 1 if $self->is_operator || $self->is_admin;

    my $dbh = $self->schema->storage->dbh;
    my $prep = $dbh->prepare('select username from server_admin where server_id = (select id from server where hostname = ?)');
    $prep->execute($hostname);
    my $res = $dbh->selectrow_hashref($prep);
    print STDERR Dumper($res, $self->current_username);
    if (my $username = $res->{username}) {
        return 1 if $self->current_username eq $username;
    }
    return 0;
}

sub ins {
    my ($self) = @_;

    my $hostname = $self->param('hostname');
    return $self->render(status => 400, text => "Mandatory argument is missing") unless $hostname;
    my $acc      = $self->current_username;
    my $kind     = $self->param('kind');
    my $msg      = $self->param('msg');

    return $self->render(status => 403, text => "User is not owner") unless $self->_has_permission($hostname);

    my $prep = $self->schema->storage->dbh->prepare('insert into server_note(hostname, dt, acc, kind, msg) values(?, now(), ?, ?, ?)');
    $prep->execute($hostname, $acc, $kind, $msg);

    return $self->render(text => $hostname, status => 201);
}

sub list {
    my ($self) = @_;

    my $hostname = $self->param("hostname");
    return $self->render(status => 400, text => "Mandatory argument is missing") unless $hostname;

    return $self->render(status => 403, text => "User is not owner") unless $self->_has_permission($hostname);


    my $sql = "select * from server_note where hostname = ?::text order by dt desc";
    $sql =~ s/::text//g unless $self->schema->pg;

    my $res = $self->schema->storage->dbh->selectall_arrayref($sql, {Columns => {}}, $hostname);

    return $self->render(json => { data => $res });
}

sub list_contact {
    my ($self) = @_;

    my $hostname = $self->param("hostname");
    return $self->render(status => 400, text => "Mandatory argument is missing") unless $hostname;
    return $self->render(status => 403, text => "User is not owner") unless $self->_has_permission($hostname);

    my $sql = "select * from server_note where hostname = ?::text and not outdated and kind = 'email'";
    $sql =~ s/::text//g unless $self->schema->pg;

    my $res = $self->schema->storage->dbh->selectall_arrayref($sql, {Columns => {}}, $hostname);

    return $self->render(json => { data => $res });
}

sub list_incident {
    my ($self) = @_;

    my $id = $self->param("id");
    return $self->render(status => 400, text => "Mandatory argument is missing") unless $id;

    my $sql = "select * from server_capability_check where server_id = ? order by dt desc";

    my $res = $self->schema->storage->dbh->selectall_arrayref($sql, {Columns => {}}, $id);

    return $self->render(json => { data => $res });
}

1;
