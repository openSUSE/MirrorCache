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

package MirrorCache::Schema::Result::AuditEvent;

use strict;
use warnings;

use base 'DBIx::Class::Core';

use DBIx::Class::Timestamps;

__PACKAGE__->table('audit_event');
__PACKAGE__->load_components(qw(InflateColumn::DateTime DynamicDefault));
__PACKAGE__->add_columns(
    id => {
        data_type         => 'integer',
        is_auto_increment => 1,
    },
    user_id => {
        data_type   => 'integer',
        is_nullable => 1
    },
    name => {
        data_type   => 'varchar',
        size        => 64,
        is_nullable => 0
    },
    event_data => {
        data_type   => 'text',
        is_nullable => 1
    },
    tag => {
        data_type   => 'int',
        is_nullable => 1
    },
    dt => {
        data_type   => 'timestamp',
        dynamic_default_on_create => 'DBIx::Class::Timestamps::now',
        is_nullable => 0
    });
__PACKAGE__->set_primary_key('id');

1;
