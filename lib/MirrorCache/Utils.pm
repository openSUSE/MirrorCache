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
use DateTime;

use Exporter 'import';

our @EXPORT_OK = qw(
  datetime_now
  random_string
  region_for_country
);


sub random_string {
    my ($length, $chars) = @_;
    $length //= 16;
    $chars  //= ['a' .. 'z', 'A' .. 'Z', '0' .. '9', '_'];
    return join('', map { $chars->[rand @$chars] } 1 .. $length);
}

sub datetime_now() {
    return DateTime->now( time_zone => 'local' )->stringify;
}

sub _round_a_bit {
    my ($size) = @_;

    if ($size < 10) {
        # give it one digit
        return int($size * 10 + .5) / 10.;
    }

    return int($size + .5);
}

sub human_readable_size {
    my ($size) = @_;

    my $p = ($size < 0) ? '-' : '';
    $size = abs($size);
    if ($size < 3000) {
        return "$p$size Byte";
    }
    $size = $size / 1024.;
    if ($size < 1024) {
        return $p . _round_a_bit($size) . "KiB";
    }

    $size /= 1024.;
    if ($size < 1024) {
        return $p . _round_a_bit($size) . "MiB";
    }

    $size /= 1024.;
    return $p . _round_a_bit($size) . "GiB";
}

# so far only countries where a mirror exists
my %_region = (
 ke => 'af',
 za => 'af',

 am => 'as',
 cn => 'as',
 hk => 'as',
 id => 'as',
 il => 'as',
 in => 'as',
 ir => 'as',
 jp => 'as',
 kr => 'as',
 my => 'as',
 om => 'as',
 sg => 'as',
 tw => 'as',
 uz => 'as',

 at => 'eu',
 be => 'eu',
 bg => 'eu',
 by => 'eu',
 ch => 'eu',
 cy => 'eu',
 cz => 'eu',
 de => 'eu',
 dk => 'eu',
 ee => 'eu',
 es => 'eu',
 fi => 'eu',
 fr => 'eu',
 gb => 'eu',
 gr => 'eu',
 hu => 'eu',
 it => 'eu',
 lv => 'eu',
 md => 'eu',
 nl => 'eu',
 no => 'eu',
 pl => 'eu',
 pt => 'eu',
 ro => 'eu',
 ru => 'eu',
 se => 'eu',
 si => 'eu',
 sk => 'eu',
 tr => 'eu',
 ua => 'eu',
 uk => 'eu',

 ca => 'na',
 cr => 'na',
 mx => 'na',
 us => 'na',

 au => 'oc',
 nz => 'oc',

 br => 'sa',
 ec => 'sa',
 uy => 'sa',
);

sub region_for_country {
    my $country = shift;
    my $reg = $_region{$country};
    return $reg;
}

1;
