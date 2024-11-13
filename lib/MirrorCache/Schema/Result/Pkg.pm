use utf8;
package MirrorCache::Schema::Result::Pkg;

use base 'DBIx::Class::Core';

use DBIx::Class::Timestamps;

__PACKAGE__->table("pkg");

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "pkg_id_seq",
  },
  "folder_id",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "metapkg_id",
  { data_type => "bigint", is_nullable => 0 },
  "t_created",
  {
    data_type   => 'timestamp',
    dynamic_default_on_create => 'DBIx::Class::Timestamps::now',
    is_nullable => 0
  }
);


__PACKAGE__->set_primary_key("id");

1;
