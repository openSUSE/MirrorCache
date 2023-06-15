# Copyright (C) 2022,2023 SUSE LLC
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

package MirrorCache::WebAPI::Controller::Rest::ReportMirror;
use Mojo::Base 'Mojolicious::Controller';

use Mojo::JSON qw(decode_json encode_json);
use Mojo::File;

my $last_cache_run;
my $cache_filename = 'reportmirror';

sub list {
    my ($c)  = @_;

    my ($report, $dt) = $c->mc->reportmirror->list;
    return $c->render(text => 'Report unavailable', status => 500) unless $report;

    $c->render(
        json => { report => $report, dt => $dt }
    );
}

1;
