use utf8;
package MirrorCache::Schema::ResultSet::Rollout;

use strict;
use warnings;

use base 'DBIx::Class::ResultSet';
use Mojo::File qw(path);

sub project_for_folder {
    my ($self, $path) = @_;
    my $dbh = $self->result_source->schema->storage->dbh;

    my $sql = <<'END_SQL';
select project.id as project_id, name, path, max(epc) as prev_epc,
  case
    when upper(name) like '%ISO%' then 'iso'
    when upper(name) ~ 'REPO|UPDATE|SOURCE|DEBUG|PORT' and ? ~ concat(path,'/?([^/]*)/repodata') then 'repo'
    else ''
  end as type,
  case
    when
      upper(name) ~ 'REPO|UPDATE|SOURCE|DEBUG|PORT'
      and ? ~ concat(path,'/?([^/]*)/repodata')
    then
      regexp_replace(?, concat(path, '/?([^/]*)/repodata'), E'\\1')
    else ''
  end as prefix
from project
left join rollout on project.id = project_id
where ? like concat(path, '%')
group by project.id, name, path
END_SQL
    unless ($dbh->{Driver}->{Name} eq 'Pg') {
        $sql =~ s/ \~ / REGEXP /g;
        $sql =~ s/E'/'/g;
    }

    my $prep = $dbh->prepare($sql);
    $prep->execute($path, $path, $path, $path);
    return $dbh->selectrow_hashref($prep);
}

# the same as project_for_folder, but also profides filename to track
sub rollout_file_for_folder {
    my ($self, $path) = @_;
    my $dbh = $self->result_source->schema->storage->dbh;

    my $sql_repo = <<'END_SQL';
select id as rollout_id, filename from
rollout
where id =
(
select max(rollout.id)
from rollout
join project on project_id = project.id
where ? = (case when length(prefix)>0 then concat(path,'/',prefix,'/repodata') else concat(path,'/repodata') end)
)
END_SQL

    my $sql_iso = <<'END_SQL';
select id as rollout_id, filename from
rollout
where id =
(
select max(rollout.id)
from rollout
join project on project_id = project.id
where ? = path
)
END_SQL

    my $sql = $sql_iso;
    $sql = $sql_repo if '/repodata' eq substr($path, -length('/repodata'));

    my $prep = $dbh->prepare($sql);
    $prep->execute($path);
    return $dbh->selectrow_hashref($prep);
}

sub add_rollout_server {
    my ($self, $rollout_id, $server_id) = @_;
    my $dbh = $self->result_source->schema->storage->dbh;

    my $sql = 'insert into rollout_server(rollout_id, server_id, dt) select ?, ?, now()';
    $dbh->prepare($sql)->execute($rollout_id, $server_id);
    return 1;
}

sub add_rollout {
    my ($self, $project_id, $epc, $version, $filename, $prefix) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql;
    $sql = <<'END_SQL';
insert into rollout(project_id, epc, version, filename, prefix, dt)
values (?, ?, ?, ?, ?, now())
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute($project_id, $epc, $version, $filename, $prefix);
}

1;
