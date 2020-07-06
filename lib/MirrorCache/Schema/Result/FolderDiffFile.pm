use utf8;
package MirrorCache::Schema::Result::FolderDiffFile;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

MirrorCache::Schema::Result::FolderDiffFile

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<folder_diff_file>

=cut

__PACKAGE__->table("folder_diff_file");

=head1 ACCESSORS

=head2 folder_diff_id

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 1

=head2 file_id

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "folder_diff_id",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 1 },
  "file_id",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 1 },
);

=head1 RELATIONS

=head2 file

Type: belongs_to

Related object: L<MirrorCache::Schema::Result::File>

=cut

__PACKAGE__->belongs_to(
  "file",
  "MirrorCache::Schema::Result::File",
  { id => "file_id" },
  {
    is_deferrable => 0,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);

=head2 folder_diff

Type: belongs_to

Related object: L<MirrorCache::Schema::Result::FolderDiff>

=cut

__PACKAGE__->belongs_to(
  "folder_diff",
  "MirrorCache::Schema::Result::FolderDiff",
  { id => "folder_diff_id" },
  {
    is_deferrable => 0,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2020-06-24 15:20:56
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:wGWIT3uCrHHZy5fTV/l6QA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
