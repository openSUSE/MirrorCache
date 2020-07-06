use utf8;
package MirrorCache::Schema::Result::ServerCapability;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

MirrorCache::Schema::Result::ServerCapability

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<server_capability>

=cut

__PACKAGE__->table("server_capability");

=head1 ACCESSORS

=head2 server_id

  data_type: 'integer'
  is_nullable: 1

=head2 capability

  data_type: 'enum'
  extra: {custom_type_name => "server_capability_t",list => ["http","https","ftp","rsync","no_ipv4","no_ipv6","yes_country","no_country","yes_region","as_only","prefix_only"]}
  is_nullable: 1

=head2 extra

  data_type: 'varchar'
  is_nullable: 1
  size: 256

=cut

__PACKAGE__->add_columns(
  "server_id",
  { data_type => "integer", is_nullable => 1 },
  "capability",
  {
    data_type => "enum",
    extra => {
      custom_type_name => "server_capability_t",
      list => [
        "http",
        "https",
        "ftp",
        "rsync",
        "no_ipv4",
        "no_ipv6",
        "yes_country",
        "no_country",
        "yes_region",
        "as_only",
        "prefix_only",
      ],
    },
    is_nullable => 1,
  },
  "extra",
  { data_type => "varchar", is_nullable => 1, size => 256 },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2020-06-24 15:20:56
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:be610154lVO1QpRfkvenow


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
