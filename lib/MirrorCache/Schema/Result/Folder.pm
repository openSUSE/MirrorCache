use utf8;
package MirrorCache::Schema::Result::Folder;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

MirrorCache::Schema::Result::Folder

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
  sequence: 'folder_id_seq'

=head2 path

  data_type: 'varchar'
  is_nullable: 0
  size: 512

=head2 files

  data_type: 'integer'
  is_nullable: 1

=head2 size

  data_type: 'bigint'
  is_nullable: 1

=cut
__PACKAGE__->load_components(qw(InflateColumn::DateTime DynamicDefault));
__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "integer",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "folder_id_seq",
  },
  "path",
  { data_type => "varchar", is_nullable => 0, size => 512 },
  wanted => {
        data_type   => 'timestamp',
        dynamic_default_on_create => 'DBIx::Class::Timestamps::now',        
        is_nullable => 1
  },
  sync_requested => {
        data_type   => 'timestamp',
        dynamic_default_on_create => 'DBIx::Class::Timestamps::now',
        is_nullable => 1
  },
  sync_scheduled => {
        data_type   => 'timestamp',
        is_nullable => 1
  },
  sync_last => {
        data_type   => 'timestamp',
        is_nullable => 1
  },
  scan_requested => {
        data_type   => 'timestamp',
        is_nullable => 1
  },
  scan_scheduled => {
        data_type   => 'timestamp',
        is_nullable => 1
  },
  scan_last => {
        data_type   => 'timestamp',
        is_nullable => 1
  },
  "size",
  { data_type => "bigint", is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<folder_path_key>

=over 4

=item * L</path>

=back

=cut

__PACKAGE__->add_unique_constraint("folder_path_key", ["path"]);

=head1 RELATIONS

=head2 files

Type: has_many

Related object: L<MirrorCache::Schema::Result::File>

=cut

__PACKAGE__->has_many(
  "files",
  "MirrorCache::Schema::Result::File",
  { "foreign.folder_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2020-06-24 15:20:56
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:/U7G7q9cOlEYX/GOvShUYA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
