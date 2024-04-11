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


1;
