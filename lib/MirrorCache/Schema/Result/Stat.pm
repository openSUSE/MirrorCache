use utf8;
package MirrorCache::Schema::Result::Stat;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table("stat");
__PACKAGE__->load_components(qw(InflateColumn::DateTime DynamicDefault));

__PACKAGE__->add_columns(
  id => {
    data_type         => 'bigint',
    is_auto_increment => 1,
  },
  "ip_sha1",
  { data_type => "char", is_nullable => 1, size => 40 },
  "agent",
  { data_type => "varchar", is_nullable => 1, size => 1024 },
  "path",
  { data_type => "varchar", is_nullable => 0, size => 1024 },
  "country",
  { data_type => "char", is_nullable => 0, size => 2 },
  "region",
  { data_type => "varchar", is_nullable => 0, size => 2 },
  "country",
  { data_type => "varchar", is_nullable => 0, size => 2 },
  "dt", 
  {
    data_type   => 'timestamp',
    dynamic_default_on_create => 'DBIx::Class::Timestamps::now',
    is_nullable => 0
  },
  "mirror_id",
  { data_type => "int", is_nullable => 1 },
  "secure",
  { data_type => "boolean", is_nullable => 0 },
  "ipv4",
  { data_type => "boolean", is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
