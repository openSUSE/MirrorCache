use utf8;
package MirrorCache::Schema::Result::FolderDiffServer;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

MirrorCache::Schema::Result::FolderDiffServer

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<folder_diff_file_server>

=cut

__PACKAGE__->table("folder_diff_server");

=head1 ACCESSORS

=head2 folder_diff_id

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 1

=head2 server_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "folder_diff_id",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 0 },
  "server_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "dt", 
  {
    data_type   => 'timestamp',
    is_nullable => 0
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("server_id");

=head1 RELATIONS

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

=head2 server

Type: belongs_to

Related object: L<MirrorCache::Schema::Result::Server>

=cut

__PACKAGE__->belongs_to(
  "server",
  "MirrorCache::Schema::Result::Server",
  { id => "server_id" },
  {
    is_deferrable => 0,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2020-06-24 15:20:56
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:yEOFNI3uQqH/I3Z2X3ZNLw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
