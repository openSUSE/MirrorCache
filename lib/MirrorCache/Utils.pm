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
# You should have received a copy of the GNU General Public License

package MirrorCache::Utils;

use strict;
use warnings;

sub random_string {
    my ($length, $chars) = @_;
    $length //= 16;
    $chars  //= ['a' .. 'z', 'A' .. 'Z', '0' .. '9', '_'];
    return join('', map { $chars->[rand @$chars] } 1 .. $length);
}

1;
