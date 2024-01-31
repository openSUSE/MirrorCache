use utf8;
package MirrorCache::Schema::ResultSet::ProjectRollout;

use strict;
use warnings;

use base 'DBIx::Class::ResultSet';
use Mojo::File qw(path);


sub project_for_folder {
    my ($self, $path) = @_;
    my $dbh = $self->result_source->schema->storage->dbh;

    my $sql = <<"END_SQL";
select id, name, path, max(epc) as prev_epc,
  case
    when upper(name) like '%ISO%' then 'iso'
    when upper(name) like '%REPO%' and ?::text = concat(path,'/repodata') then 'repo'
    else ''
  end as type
from project
left join project_rollout on id = project_id
where ? like concat(path, '/%')
group by id, name, path
END_SQL
    $sql =~ s/::text//g unless ($dbh->{Driver}->{Name} eq 'Pg');

    my $prep = $dbh->prepare($sql);
    $prep->execute($path, $path);
    return $dbh->selectrow_hashref($prep);
}

# the same as project_for_folder, but also profides filename to track
sub rollout_file_for_folder {
    my ($self, $path) = @_;
    my $dbh = $self->result_source->schema->storage->dbh;

    my $sql = <<"END_SQL";
select id, name, path, epc, filename
from (
select id, name, path, max(epc) as prev_epc,
  case
    when upper(name) like '%ISO%' then 'iso'
    when upper(name) like '%REPO%' and ?::text = concat(path,'/repodata') then 'repo'
    else ''
  end as type
from project
join project_rollout on id = project_id
where ? like concat(path, '/%')
group by id, name, path
) rollout
join project_rollout on (id, prev_epc) = (project_id, epc) and type != ''
END_SQL
    $sql =~ s/::text//g unless ($dbh->{Driver}->{Name} eq 'Pg');

    my $prep = $dbh->prepare($sql);
    $prep->execute($path, $path);
    return $dbh->selectrow_hashref($prep);
}

sub add_rollout_server {
    my ($self, $server_id, $proj_id, $epc) = @_;
    my $dbh = $self->result_source->schema->storage->dbh;

    my $sql = 'insert into project_rollout_server(server_id, project_id, epc, dt) select ?, ?, ?, now()';
    $dbh->prepare($sql)->execute($server_id, $proj_id, $epc);
    return 1;
}

1;
