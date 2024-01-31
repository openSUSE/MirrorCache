use utf8;
package MirrorCache::Schema::Result::ProjectRollout;

use strict;
use warnings;

use base 'DBIx::Class::Core';
use DBIx::Class::Timestamps;

__PACKAGE__->table("project_rollout");


__PACKAGE__->load_components(qw(InflateColumn::DateTime DynamicDefault));
__PACKAGE__->add_columns(
  "project_id",
  { data_type => "integer"},
  "epc",
  { data_type => "integer"},
  "dt",
  {
        data_type   => 'timestamp',
        is_nullable => 1
  },
  version => {
        data_type   => 'varchar',
        size => 32
  },
);

1;
