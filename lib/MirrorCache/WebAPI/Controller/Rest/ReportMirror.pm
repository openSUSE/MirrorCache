# Copyright (C) 2022 SUSE LLC
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
use Data::Dumper;

sub list {
    my ($self)  = @_;

    my $sql = 'select dt, body from report_body where report_id = 1 order by dt desc limit 1';

    eval {
        my @res = $self->schema->storage->dbh->selectrow_array($sql);
        my $body = $res[1];
        my $hash = decode_json($body);

        $self->render(
            json => { report => $hash, dt => $res[0] }
        );
    };
    my $error = $@;
    if ($error) {
         print STDERR "RESPMIRRORREPORT : " . $error . "\n";
         return $self->render(json => {error => $error}, status => 404);
    }
}

1;
