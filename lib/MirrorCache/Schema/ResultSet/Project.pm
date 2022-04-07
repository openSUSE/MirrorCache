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
select sum(case when diff = 0 then 1 else 0 end) as current, sum(case when diff = 0 then 0 else 1 end) as outdated
from (
select server_id, max(case when d1 <> d2 then 1 else 0 end) diff
from (
select prj.etalon, f.path, f.id, fd.folder_id, fds.server_id, fds.folder_diff_id as d1, fds2.folder_diff_id as d2
from project prj
join folder f on f.path like concat(prj.path,'/%')
join folder_diff fd on fd.folder_id = f.id
join folder_diff fd2 on fd2.folder_id = fd.folder_id
join folder_diff_server fds on fd.id = fds.folder_diff_id
join folder_diff_server fds2 on fd2.id = fds2.folder_diff_id and fds2.server_id = prj.etalon
where prj.name = ?
) x
group by server_id) xx
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute($name);
    return $dbh->selectrow_hashref($prep);
}

sub mirror_list {
    my ($self, $name) = @_;
    my $dbh = $self->result_source->schema->storage->dbh;

    my $sql = <<"END_SQL";
select server_id, min(case when d1 = d2 then 1 else 0 end) as current, concat(s.hostname, s.urldir) as url
from (
select fds.server_id, fds.folder_diff_id as d1, fds2.folder_diff_id as d2
from project prj
join folder f on f.path like concat(prj.path,'/%')
join folder_diff fd on fd.folder_id = f.id
join folder_diff fd2 on fd2.folder_id = fd.folder_id
join folder_diff_server fds on fd.id = fds.folder_diff_id
join folder_diff_server fds2 on fd2.id = fds2.folder_diff_id and fds2.server_id = prj.etalon
where prj.name = ?
) x
join server s on x.server_id = s.id
group by x.server_id, s.id
order by current desc, url
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute($name);
    return $dbh->selectall_arrayref($prep, { Slice => {} });
}

1;
