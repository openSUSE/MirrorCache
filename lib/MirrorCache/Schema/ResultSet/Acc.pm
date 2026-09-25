# Copyright (C) 2020 LLC
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

package MirrorCache::Schema::ResultSet::Acc;

use strict;
use warnings;

use base 'DBIx::Class::ResultSet';

sub create_user {
    my ($self, $id, %attrs) = @_;

    return unless $id;
    $attrs{username} = $id;
    $attrs{provider} //= '';

    my $existing_user = $self->find({username => $id});
    if ($existing_user && ($existing_user->provider // '') ne $attrs{provider}) {
        die "Auth provider mismatch: Account '$id' is registered via '"
          . ($existing_user->provider || 'default')
          . "', but login attempted via '$attrs{provider}'. Admin migration required.\n";
    }

    my $user = $self->update_or_new(\%attrs);

    if (!$user->in_storage) {
        if (not $self->find({is_admin => 1}, {rows => 1})) {
            if ($user->email && $user->email =~ /suse.com$/) {
                $user->is_admin(1);
                $user->is_operator(1);
            }
        }
        $user->insert;
    }
    return $user;
}

1;
