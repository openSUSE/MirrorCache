use utf8;
package MirrorCache::Schema::Result::Metapkg;

use base 'DBIx::Class::Core';

use DBIx::Class::Timestamps;

__PACKAGE__->table("metapkg");


__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "pkg_id_seq",
  },
  "name",
  { data_type => "varchar", is_nullable => 0, size => 512 },
  "t_created",
  {
    data_type   => 'timestamp',
    dynamic_default_on_create => 'DBIx::Class::Timestamps::now',
    is_nullable => 0
  }
);


__PACKAGE__->set_primary_key("id");

1;
