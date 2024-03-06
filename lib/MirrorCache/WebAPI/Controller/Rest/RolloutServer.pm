# Copyright (C) 2024 SUSE LLC
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

package MirrorCache::WebAPI::Controller::Rest::RolloutServer;
use Mojo::Base 'Mojolicious::Controller';
use Data::Dumper;

sub list {
    my ($self) = @_;

    my $version = $self->param("version");

    return $self->render(code => 400, text => "Mandatory argument is missing") unless $version;

    my $sql = <<'END_SQL';
select rollout_id, name as project, version, scan_dt as time, server_id, hostname as mirror
from
rollout
join rollout_server on rollout_id = rollout.id
join project on project_id = project.id
left join server on server_id = server.id
where version = ?
order by scan_dt desc
END_SQL

    my $res = $self->schema->storage->dbh->selectall_arrayref($sql, {Columns => {}}, $version);

    return $self->render(json => { data => $res });
}

1;
