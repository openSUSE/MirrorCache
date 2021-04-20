use utf8;
package MirrorCache::Schema::Result::Demand;

use strict;
use warnings;

use base 'DBIx::Class::Core';
use DBIx::Class::Timestamps;

__PACKAGE__->table("demand");

__PACKAGE__->add_columns(
  "folder_id",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 1 },
  "country",
  { data_type => "varchar", is_nullable => 0, size => 2 },
  "last_request",
  {
    data_type   => 'timestamp',
    is_nullable => 0
  },
  "last_scan",
  {
    data_type   => 'timestamp',
    is_nullable => 1
  }
);

1;
