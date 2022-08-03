use utf8;
package MirrorCache::Schema::ResultSet::Project;

use strict;
use warnings;

use base 'DBIx::Class::ResultSet';
use Mojo::File qw(path);


sub mirror_summary {
    my ($self, $name) = @_;
    my $dbh = $self->result_source->schema->storage->dbh;

    my $sql = <<"END_SQL";
    select sum(case when diff = 0 then 1 else 0 end) as current, sum(case when diff = 0 or diff is null then 0 else 1 end) as outdated
from (
select
    server_id,
    max(case when d1 <> d2 or d1 is null then 1 else 0 end) diff
from (
select s.id as server_id, prj.name, fds.folder_diff_id d1, fds2.folder_diff_id d2
from server s
join project prj on prj.name = ?
join folder f on f.path like concat(prj.path,'/%')
join folder_diff fd on fd.folder_id = f.id
left join folder_diff_server fds  on fds.folder_diff_id = fd.id and fds.server_id = s.id
join folder_diff_server fds2 on fds2.folder_diff_id = fd.id and fds2.server_id = prj.etalon
) x
group by server_id
having  sum(case when d1 is not null then 1 else 0 end) > 0
) xx
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute($name);
    return $dbh->selectrow_hashref($prep);
}

sub mirror_list {
    my ($self, $name) = @_;
    my $dbh = $self->result_source->schema->storage->dbh;

    my $sql = <<"END_SQL";
select
    s.id server_id,
    min(case when d1 = d2 then 1 else 0 end) as current,
    concat(s.hostname, s.urldir) as url
from (
select s.id as server_id, prj.name, fds.folder_diff_id d1, fds2.folder_diff_id d2
from server s
join project prj on prj.name = ?
join folder f on f.path like concat(prj.path,'/%')
join folder_diff fd on fd.folder_id = f.id
left join folder_diff_server fds  on fds.folder_diff_id = fd.id and fds.server_id = s.id
join folder_diff_server fds2 on fds2.folder_diff_id = fd.id and fds2.server_id = prj.etalon
) x
join server s on x.server_id = s.id
group by s.id, s.hostname, s.urldir
having sum(case when d1 is not null then 1 else 0 end) > 0
order by current desc, url
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute($name);
    return $dbh->selectall_arrayref($prep, { Slice => {} });
}

1;
