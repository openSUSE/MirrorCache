use utf8;
package MirrorCache::Schema::Result::Subsidiary;

=head1 NAME

MirrorCache::Schema::Result::Subsidiary

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<subsidiary>

=cut

__PACKAGE__->table("subsidiary");

=head1 ACCESSORS

=head2 region

  data_type: 'varchar'
  is_nullable: 0
  size: 2

=head2 hostname

  data_type: 'varchar'
  is_nullable: 0
  size: 128

=head2 uri

  data_type: 'varchar'
  is_nullable: 1
  size: 128


=cut

__PACKAGE__->add_columns(
  "region",
  { data_type => "varchar", is_nullable => 0, size => 2 },
  "hostname",
  { data_type => "varchar", is_nullable => 0, size => 128 },
  "uri",
  { data_type => "varchar", is_nullable => 0, size => 128 },
);
1;
