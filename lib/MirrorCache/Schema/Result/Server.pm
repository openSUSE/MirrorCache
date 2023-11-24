use utf8;
package MirrorCache::Schema::Result::Server;

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
  "sponsor",
  { data_type => "varchar", is_nullable => 1, size => 64 },
  "sponsor_url",
  { data_type => "varchar", is_nullable => 1, size => 64 },
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

__PACKAGE__->has_many(
  "folder_diff_file_servers",
  "MirrorCache::Schema::Result::FolderDiffFileServer",
  { "foreign.server_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

__PACKAGE__->has_many(
  "server_admin",
  "MirrorCache::Schema::Result::ServerAdmin",
  { "foreign.server_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


__PACKAGE__->has_many(
  "server_capability_declaration",
  "MirrorCache::Schema::Result::ServerCapabilityDeclaration",
  sub {
    my $args = shift;
    return { 
        "$args->{foreign_alias}.server_id" => { -ident => "$args->{self_alias}.id" },
        "$args->{foreign_alias}.extra"     => { '=', 'region' },
    };
  },
  { cascade_copy => 0, cascade_delete => 0, join_type => 'left' },
);

1;
