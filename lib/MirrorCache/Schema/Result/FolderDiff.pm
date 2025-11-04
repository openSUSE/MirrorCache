use utf8;
package MirrorCache::Schema::Result::FolderDiff;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

MirrorCache::Schema::Result::FolderDiff

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<folder_diff>

=cut

__PACKAGE__->table("folder_diff");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'folder_diff_id_seq'

=head2 folder_id

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 1

=head2 hash

  data_type: 'varchar'
  is_nullable: 1
  size: 40

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "folder_diff_id_seq",
  },
  "folder_id",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 1 },
  "hash",
  { data_type => "varchar", is_nullable => 1, size => 40 },
  "dt",
  {
    data_type   => 'timestamp',
    is_nullable => 0
  },
  "mtime_latest",
  { data_type => 'bigint' },
  "realfolder_id",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 folder

Type: belongs_to

Related object: L<MirrorCache::Schema::Result::Miss>

=cut

__PACKAGE__->belongs_to(
  "folder",
  "MirrorCache::Schema::Result::Miss",
  { id => "folder_id" },
  {
    is_deferrable => 0,
    join_type     => "LEFT",
    on_delete     => "CASCADE",
    on_update     => "NO ACTION",
  },
);

=head2 folder_diff_file_servers

Type: has_many

Related object: L<MirrorCache::Schema::Result::FolderDiffFileServer>

=cut

__PACKAGE__->has_many(
  "folder_diff_file_servers",
  "MirrorCache::Schema::Result::FolderDiffFileServer",
  { "foreign.folder_diff_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 folder_diff_files

Type: has_many

Related object: L<MirrorCache::Schema::Result::FolderDiffFile>

=cut

__PACKAGE__->has_many(
  "folder_diff_files",
  "MirrorCache::Schema::Result::FolderDiffFile",
  { "foreign.folder_diff_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2020-06-24 15:20:56
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:GXIVl9CoKqDFf5Brm6axCw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
