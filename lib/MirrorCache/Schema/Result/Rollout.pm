use utf8;
package MirrorCache::Schema::Result::Rollout;

use strict;
use warnings;

use base 'DBIx::Class::Core';
use DBIx::Class::Timestamps;

__PACKAGE__->table("rollout");


__PACKAGE__->load_components(qw(InflateColumn::DateTime DynamicDefault));
__PACKAGE__->add_columns(
  "id",
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
  prefix => {
        data_type   => 'varchar',
        size => 32
  },
);

1;
