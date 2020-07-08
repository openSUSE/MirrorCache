use utf8;
package MirrorCache::Schema::Result::File;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

MirrorCache::Schema::Result::File

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';
use DBIx::Class::Timestamps;

=head1 TABLE: C<file>

=cut

__PACKAGE__->table("file");
__PACKAGE__->load_components(qw(InflateColumn::DateTime DynamicDefault));

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'file_id_seq'

=head2 folder_id

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 1

=head2 name

  data_type: 'varchar'
  is_nullable: 1
  size: 512

=head2 name

  data_type: 'dt'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "bigint",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "file_id_seq",
  },
  "folder_id",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 1 },
  "name",
  { data_type => "varchar", is_nullable => 1, size => 512 },
  "dt", 
  {
    data_type   => 'timestamp',
    dynamic_default_on_create => 'DBIx::Class::Timestamps::now',
    is_nullable => 0
  }
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<file_folder_id_name_key>

=over 4

=item * L</folder_id>

=item * L</name>

=back

=cut

__PACKAGE__->add_unique_constraint("file_folder_id_name_key", ["folder_id", "name"]);

=head1 RELATIONS

=head2 folder

Type: belongs_to

Related object: L<MirrorCache::Schema::Result::Folder>

=cut

__PACKAGE__->belongs_to(
  "folder",
  "MirrorCache::Schema::Result::Folder",
  { id => "folder_id" },
  {
    is_deferrable => 0,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);

=head2 folder_diff_files

Type: has_many

Related object: L<MirrorCache::Schema::Result::FolderDiffFile>

=cut

__PACKAGE__->has_many(
  "folder_diff_files",
  "MirrorCache::Schema::Result::FolderDiffFile",
  { "foreign.file_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2020-06-24 15:20:56
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:zQcGqor3h/DEthp5ie+f5g


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
