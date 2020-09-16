# Copyright (C) 2020 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

package MirrorCache::Schema::Result::Acc;

use strict;
use warnings;

use base 'DBIx::Class::Core';

use URI::Escape 'uri_escape';
use Digest::MD5 'md5_hex';

__PACKAGE__->table('acc');
__PACKAGE__->load_components(qw(InflateColumn::DateTime Timestamps));
__PACKAGE__->add_columns(
    id => {
        data_type         => 'integer',
        is_auto_increment => 1,
    },
    username => {
        data_type   => 'varchar',
        size        => 64,
    },
    email => {
        data_type   => 'varchar',
        size        => 128,
    },
    fullname => {
        data_type   => 'varchar',
        size        => 128,
    },
    nickname => {
        data_type   => 'varchar',
        size        => 64,
    },
    is_operator => {
        data_type     => 'integer',
        is_boolean    => 1,
        false_id      => ['0', '-1'],
        default_value => '0',
    },
    is_admin => {
        data_type     => 'integer',
        is_boolean    => 1,
        false_id      => ['0', '-1'],
        default_value => '0',
    },
);
__PACKAGE__->add_timestamps;
__PACKAGE__->set_primary_key('id');
__PACKAGE__->add_unique_constraint([qw(username)]);

sub name {
    my ($self) = @_;

    if (!$self->{_name}) {
        $self->{_name} = $self->nickname;
        if (!$self->{_name}) {
            $self->{_name} = $self->username;
        }
    }
    return $self->{_name};
}

1;
