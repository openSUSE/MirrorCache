use utf8;
package MirrorCache::Schema::Result::Redirect;

=head1 NAME

MirrorCache::Schema::Result::Redirect

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

use DBIx::Class::Timestamps;

=head1 TABLE: C<folder>

=cut

__PACKAGE__->table("folder");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'redirect_id_seq'

=head2 pathfrom

  data_type: 'varchar'
  is_nullable: 0
  size: 512

=head2 pathto

  data_type: 'varchar'
  is_nullable: 0
  size: 512

=cut
__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "integer",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "redirect_id_seq",
  },
  "pathfrom",
  { data_type => "varchar", is_nullable => 0, size => 512 },
  "pathto",
  { data_type => "varchar", is_nullable => 0, size => 512 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<redirect_pathfrom_key>

=over 4

=item * L</pathfrom>

=back

=cut

__PACKAGE__->add_unique_constraint("redirect_pathfrom_key", ["pathfrom"]);

1;
