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

package MirrorCache::WebAPI::Controller::Rest::ProjectPropagation;
use Mojo::Base 'Mojolicious::Controller';
use Data::Dumper;

sub list {
    my ($self) = @_;

    my $project_id = $self->param("project_id");

    return $self->render(code => 400, text => "Mandatory argument is missing") unless $project_id;

    my $sql = <<'END_SQL';
with propagation as (
select prefix, rollout_server.dt, epc, version, count(*) as mirror_count
from
rollout_server
join rollout on id = rollout_id
where rollout.project_id = ?
group by prefix, version, epc, rollout_server.dt
)
select p2.prefix, p2.dt, p2.version, sum(p1.mirror_count) as mirrors
from propagation p1
join propagation p2 on p1.epc = p2.epc and p1.dt <= p2.dt and p1.prefix = p2.prefix
group by p2.prefix, p2.dt, p2.version
order by p2.dt desc
END_SQL

    my $res = $self->schema->storage->dbh->selectall_arrayref($sql, {Columns => {}}, $project_id);

    return $self->render(json => { data => $res });
}

1;
