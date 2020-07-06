use utf8;
package MirrorCache::Schema::Result::Miss;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

MirrorCache::Schema::Result::Miss

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<miss>

=cut

__PACKAGE__->table("miss");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'miss_id_seq'

=head2 folder_id

  data_type: 'integer'
  is_nullable: 1

=head2 requested

  data_type: 'timestamp'
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "miss_id_seq",
  },
  "folder_id",
  { data_type => "integer", is_nullable => 1 },
  "requested",
  { data_type => "timestamp", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 folder_diffs

Type: has_many

Related object: L<MirrorCache::Schema::Result::FolderDiff>

=cut

__PACKAGE__->has_many(
  "folder_diffs",
  "MirrorCache::Schema::Result::FolderDiff",
  { "foreign.folder_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2020-06-24 15:20:56
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:45d3aOiJNMmjZhOBL6pLYg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
