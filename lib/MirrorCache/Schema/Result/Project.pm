use utf8;
package MirrorCache::Schema::Result::Project;

use strict;
use warnings;

use base 'DBIx::Class::Core';
use DBIx::Class::Timestamps;

__PACKAGE__->table("project");


__PACKAGE__->load_components(qw(InflateColumn::DateTime DynamicDefault));
__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "integer",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "project_id_seq",
  },
  "name",
  { data_type => "varchar", is_nullable => 0, size => 64 },
  "path",
  { data_type => "varchar", is_nullable => 0, size => 512 },
  "redirect",
  { data_type => "varchar", is_nullable => 0, size => 512 },
  db_sync_last => {
        data_type   => 'timestamp',
        is_nullable => 1
  },
  prio => { data_type => "integer", is_nullable => 1 },
  db_sync_every => {
        data_type   => 'integer',
        is_nullable => 1
  },
  db_sync_full_every => { data_type => "integer", is_nullable => 1 },
);


__PACKAGE__->set_primary_key("id");
1;
