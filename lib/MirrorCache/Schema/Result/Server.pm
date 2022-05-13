use utf8;
package MirrorCache::Schema::Result::Server;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

MirrorCache::Schema::Result::Server

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<server>

=cut

__PACKAGE__->table("server");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0
  sequence: 'server_id_seq'

=head2 hostname

  data_type: 'varchar'
  is_nullable: 0
  size: 128

=head2 urldir

  data_type: 'varchar'
  is_nullable: 0
  size: 128

=head2 enabled

  data_type: 'boolean'
  is_nullable: 0

=head2 region

  data_type: 'varchar'
  is_nullable: 0
  size: 2

=head2 country

  data_type: 'varchar'
  is_nullable: 0
  size: 2

=head2 score

  data_type: 'smallint'
  is_nullable: 0

=head2 comment

  data_type: 'text'
  is_nullable: 0

=head2 public_notes

  data_type: 'varchar'
  is_nullable: 0
  size: 512

=head2 lat

  data_type: 'numeric'
  is_nullable: 1
  size: [6,3]

=head2 lng

  data_type: 'numeric'
  is_nullable: 1
  size: [6,3]

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type         => "integer",
    is_auto_increment => 1,
    is_nullable       => 0,
    sequence          => "server_id_seq",
  },
  "hostname",
  { data_type => "varchar", is_nullable => 0, size => 128 },
  "urldir",
  { data_type => "varchar", is_nullable => 0, size => 128 },
  "enabled",
  { data_type => "boolean", is_nullable => 0 },
  "region",
  { data_type => "varchar", is_nullable => 0, size => 2 },
  "country",
  { data_type => "varchar", is_nullable => 0, size => 2 },
  "score",
  { data_type => "smallint", is_nullable => 0 },
  "comment",
  { data_type => "text", is_nullable => 0 },
  "public_notes",
  { data_type => "varchar", is_nullable => 0, size => 512 },
  "lat",
  { data_type => "numeric", is_nullable => 1, size => [6, 3] },
  "lng",
  { data_type => "numeric", is_nullable => 1, size => [6, 3] },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 folder_diff_file_servers

Type: has_many

Related object: L<MirrorCache::Schema::Result::FolderDiffFileServer>

=cut

__PACKAGE__->has_many(
  "folder_diff_file_servers",
  "MirrorCache::Schema::Result::FolderDiffFileServer",
  { "foreign.server_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

__PACKAGE__->has_many(
  "server_admin",
  "MirrorCache::Schema::Result::ServerAdmin",
  { "foreign.server_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

1;
