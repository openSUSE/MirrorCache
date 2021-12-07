use utf8;
package MirrorCache::Schema::Result::Hash;

use strict;
use warnings;

use base 'DBIx::Class::Core';
use DBIx::Class::Timestamps;

__PACKAGE__->table("hash");
__PACKAGE__->load_components(qw(InflateColumn::DateTime DynamicDefault));

__PACKAGE__->add_columns(
  "file_id",
  { data_type => "bigint",
    is_auto_increment => 1,
    is_foreign_key => 1
  },
  "mtime",
  { data_type => "bigint" },
  "size",
  { data_type => "bigint", is_nullable => 0 },
  "md5",
  { data_type => "char", size => 32 },
  "sha1",
  { data_type => "char", size => 40 },
  "sha256",
  { data_type => "char", size => 64 },
  "piece_size",
  { data_type => "int" },
  "pieces",
  { data_type => "text" },
  "target",
  { data_type => "varchar", size => 512 },
  "dt",
  {
    data_type   => 'timestamp',
    dynamic_default_on_create => 'DBIx::Class::Timestamps::now',
    is_nullable => 0
  }
);

1;
