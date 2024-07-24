use utf8;
package MirrorCache::Schema::ResultSet::Project;

use strict;
use warnings;

use base 'DBIx::Class::ResultSet';

sub mark_scheduled {
    my ($self, $project_id) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = << "END_SQL";
update project
set db_sync_last = CURRENT_TIMESTAMP(3)
where id = ?
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute($project_id);
}

sub update_disk_usage {
    my ($self, $path, $size, $file_cnt, $lm) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = << "END_SQL";
update project set
size = ?,
file_cnt = ?,
lm = (case when lm > ? then lm else ? end)
where path = ?
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute($size, $file_cnt, $lm, $lm, $path);
}

1;
