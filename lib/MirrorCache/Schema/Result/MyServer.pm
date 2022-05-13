use utf8;
package MirrorCache::Schema::Result::MyServer;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table("server");

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "integer",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "server_id_seq",
  },
  "hostname",
  { data_type => "varchar", is_nullable => 0, size => 128 },
  "urldir",
  { data_type => "varchar", is_nullable => 0, size => 128 },
  "enabled",
  { data_type => "boolean", is_nullable => 0 },
  "region",
  { data_type => "varchar", is_nullable => 0, size => 2 },
  "country",
  { data_type => "varchar", is_nullable => 0, size => 2 },
  "score",
  { data_type => "smallint", is_nullable => 0 },
  "comment",
  { data_type => "text", is_nullable => 0 },
  "public_notes",
  { data_type => "varchar", is_nullable => 0, size => 512 },
  "lat",
  { data_type => "numeric", is_nullable => 1, size => [6, 3] },
  "lng",
  { data_type => "numeric", is_nullable => 1, size => [6, 3] },
);

__PACKAGE__->set_primary_key("id");

# __PACKAGE__->has_many('id' => 'MirrorCache::Schema::Result::ServerAdmin');

1;
