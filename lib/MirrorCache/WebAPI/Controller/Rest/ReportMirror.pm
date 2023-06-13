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
use Mojo::File;

my $last_cache_run;
my $cache_filename = 'reportmirror';

# Prototype below is a hack trying to achive:
# - If there are subsidiaries (i.e. tag is not empty) - merge reports from DB for each subsidiary.
# - If successfully read report from DB - save the structures into cache folder (eventually for each subsidiary as well); max - once per minute
# - If there was an error reading from DB - show the structures from the cache
sub list {
    my ($self)  = @_;

    my $sql = 'select dt, body, tag from report_body where report_id = 1 order by dt desc limit 1';

    my $body;
    my %body_reg;
    my $dt;
    my %dt_reg;
    my $waserror = 1;
    eval {
        my @res = $self->schema->storage->dbh->selectrow_array($sql);
        my $tag = $res[2];
        if ($tag) {
            $body = $self->_render_geo_from_db(\%body_reg, \%dt_reg);
        } else {
            $dt   = $res[0];
            $body = $res[1];
            my $report = decode_json($body);

            $self->render(
                json => { report => $report, dt => $res[0] }
            );
        }
        $waserror = 0;
    };
    my $error = $@;
    if ($waserror) {
        my $report;
        eval {
            my $f = Mojo::File->new( $self->mcproject->cache_dir . "/$cache_filename.json" );
            $body = $f->slurp;
            return unless $body;
            $report = decode_json($body);
            my @report = @{ $report };
            my @regions = $self->subsidiary->regions;
            for my $region (@regions) {
                next unless $region;
                next if $self->subsidiary->is_local($region);
                eval {
                    my $f_reg = Mojo::File->new( $self->mcproject->cache_dir . "/$cache_filename$region.json" );
                    my $bodyreg = $f_reg->slurp;
                    my $json = decode_json($bodyreg) if $bodyreg;
                    next unless $json;
                    my @items = @{ $json };
                    if (my $url = $self->subsidiary->url($region)) {
                        for my $item (@items) {
                            $item->{region} = ($item->{region} // '') . " ($url)";
                        }
                    }
                    push @report, @items;
                };
            }
            $report = \@report;
        };
        return $self->render(
            json => { report => $report }
        ) if $report;

        return $self->render(json => {error => $error}, status => 404);
    }

    return unless $self->mcproject->caching;

    if (!$last_cache_run || 60 < time() - $last_cache_run) {
        $last_cache_run = time();
        eval {
            my $f = Mojo::File->new( $self->mcproject->cache_dir . "/$cache_filename.json" );
            $f->spurt($body) if $body;
            my @regions = $self->subsidiary->regions;
            for my $region (@regions) {
                my $x = $body_reg{$region};
                next unless $x;
                $f = Mojo::File->new( $self->mcproject->cache_dir . "/$cache_filename$region.json" );
                $f->spurt($x);
            }
            1;
        }
    }
}

sub _render_geo_from_db {
    my ($self, $body_reg, $dt_reg) = @_;
    my $sql = 'select dt, body, tag from report_body where report_id = 1 and tag = ? order by dt desc limit 1';
    my @res = $self->schema->storage->dbh->selectrow_array($sql, {}, 'local');
    my $body = $res[1];
    my $report = decode_json($body);
    my @report = @$report;
    my %regions_res;
    my @regions = $self->subsidiary->regions;
    for my $region (@regions) {
        next if $self->subsidiary->is_local($region);
        my @res_reg = $self->schema->storage->dbh->selectrow_array($sql, {}, $region);
        next unless @res_reg;
        my $dtreg   = $res_reg[0];
        my $bodyreg = $res_reg[1];
        my $json = decode_json($bodyreg);
        my @items = @{ $json->{report} };
        $body_reg->{$region} = encode_json(\@items);
        $dt_reg->{$region}   = $dtreg;
        my $url = $self->subsidiary->url($region);
        for my $item (@items) {
            $item->{region} = $item->{region} . " ($url)";
        }
        push @report, @items if @items;
    }
    $self->render(
        json => { report => \@report, dt => $res[0] }
    );
    return $body;
}

1;
