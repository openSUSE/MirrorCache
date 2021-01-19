use utf8;
package MirrorCache::Schema::Result::ServerCapabilityDeclaration;

=head1 NAME

MirrorCache::Schema::Result::ServerCapabilityDeclaration

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<server_capability_declaration>

=cut

__PACKAGE__->table("server_capability_declaration");

__PACKAGE__->add_columns(
  "server_id",
  { data_type => "integer", is_nullable => 0 },
  "capability",
  {
    data_type => "enum",
    extra => {
      custom_type_name => "server_capability_t",
      list => [
        "http",
        "https",
        "ftp",
        "ftps",
        "rsync",
        "ipv4",
        "ipv6",
        "country",
        "region",
        "as",
        "prefix",
      ],
    },
    is_nullable => 1,
  },
  enabled => {
      data_type     => 'integer',
      is_boolean    => 1,
      false_id      => ['0', '-1'],
      default_value => '0',
  },
  "extra",
  { data_type => "varchar", is_nullable => 1, size => 256 },
);

1;
