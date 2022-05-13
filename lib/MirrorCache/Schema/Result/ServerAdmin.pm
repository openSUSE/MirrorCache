use utf8;
package MirrorCache::Schema::Result::ServerAdmin;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table("server_admin");

__PACKAGE__->add_columns(
  "server_id",
  {
    data_type         => "integer",
    is_nullable       => 0,
  },
  "username",
  { data_type => "varchar", is_nullable => 0, size => 128 },
);

__PACKAGE__->set_primary_key("server_id", "username");
# __PACKAGE__->has_one('server_id' => 'MirrorCache::Schema::Result::Server');

1;
