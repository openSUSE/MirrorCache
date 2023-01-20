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

package MirrorCache::WebAPI::Controller::Rest::ServerLocation;
use Mojo::Base 'Mojolicious::Controller';
use Data::Dumper;

sub update_location {
    my ($self) = @_;

    my $id = $self->param("id");
    return $self->render(code => 400, text => "Mandatory argument is missing") unless $id;

    my $job_id;
    eval {
        $job_id = $self->minion->enqueue('mirror_location' => [$id] => {priority => 5});
    };
    return $self->render(code => 500, text => Dumper($@)) unless $job_id;

    return $self->render(
        json => {
            job_id     => $job_id,
        }
    );
}

sub list {
    my ($self) = @_;

    my $region = $self->param("region");

    return $self->render(code => 501, text => 'Expected parameter "region"') unless $region;

    my $sql = "select * from server where region = ? or exists( select 1 from server_capability_declaration where server_id = server.id and capability = 'region' and concat(',', extra, ',') like concat('%',?::text,'%'));";

    $sql =~ s/::text//g unless $self->schema->pg;


    my $res = $self->schema->storage->dbh->selectall_arrayref($sql, {Columns => {}}, $region, $region);

    return $self->render(json => $res);
}

1;
