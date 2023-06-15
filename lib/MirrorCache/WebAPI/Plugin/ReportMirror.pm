# Copyright (C) 2023 SUSE LLC
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

package MirrorCache::WebAPI::Plugin::ReportMirror;
use Mojo::Base 'Mojolicious::Plugin';

use Mojo::JSON qw(decode_json encode_json);
use Mojo::File;

my $last_cache_run; # last time when we saved reports into cache
my $last_error; # used to not spam log with errors

my $cache_filename = 'reportmirror';

sub register {
    my ($c, $app) = @_;

    $app->helper('mc.reportmirror.list' => \&_list);
    return $c;
}

# Prototype below is a hack trying to achive:
# - If there are subsidiaries (i.e. tag is not empty) - merge reports from DB for each subsidiary.
# - If successfully read report from DB - save the structures into cache folder (eventually for each subsidiary as well); max - once per minute
# - If there was an error reading from DB - show the structures from the cache
sub _list {
    my ($c)  = @_;

    my $sql = 'select dt, body, tag from report_body where report_id = 1 order by dt desc limit 1';

    my $body;
    my %body_reg;
    my %dt_reg;
    my $waserror = 1;
    my ($report, $dt);
    eval {
        my @res = $c->schema->storage->dbh->selectrow_array($sql);
        my $tag = $res[2];
        if ($tag) {
            ($report, $dt, $body) = _list_geo_from_db($c, \%body_reg, \%dt_reg);
        } else {
            $dt   = $res[0];
            $body = $res[1];
            $report = decode_json($body);
        }
        $waserror = 0;
    };
    my $error = $@;
    if ($waserror) {
        eval {
            my $f = Mojo::File->new( $c->mcproject->cache_dir . "/$cache_filename.json" );
            $body = $f->slurp;
            return unless $body;
            $report = decode_json($body);
            my @report = @{ $report };
            my @regions = $c->subsidiary->regions;
            for my $region (@regions) {
                next unless $region;
                next if $c->subsidiary->is_local($region);
                eval {
                    my $f_reg = Mojo::File->new( $c->mcproject->cache_dir . "/$cache_filename$region.json" );
                    my $bodyreg = $f_reg->slurp;
                    my $json = decode_json($bodyreg) if $bodyreg;
                    next unless $json;
                    my @items = @{ $json };
                    if (my $url = $c->subsidiary->url($region)) {
                        for my $item (@items) {
                            $item->{region} = ($item->{region} // '') . " ($url)";
                        }
                    }
                    push @report, @items;
                };
            }
            $report = \@report;
        };

        if (!$last_error || 300 < time() - $last_error ) {
            $c->log->error("Error while loading report: " . ($error // 'Unknown'));
        }
    } elsif ($c->mcproject->caching && (!$last_cache_run || 60 < time() - $last_cache_run)) {
        $last_cache_run = time();
        eval {
            my $f = Mojo::File->new( $c->mcproject->cache_dir . "/$cache_filename.json" );
            $f->spurt($body) if $body;
            my @regions = $c->subsidiary->regions;
            for my $region (@regions) {
                my $x = $body_reg{$region};
                next unless $x;
                $f = Mojo::File->new( $c->mcproject->cache_dir . "/$cache_filename$region.json" );
                $f->spurt($x);
            }
            1;
        }
    }
    return ($report, $dt);
}

# $body_reg will contain report for each subsidiary, so we can cache them later
# $dt_reg contains time of report for each region
sub _list_geo_from_db {
    my ($c, $body_reg, $dt_reg) = @_;
    my $sql = 'select dt, body, tag from report_body where report_id = 1 and tag = ? order by dt desc limit 1';
    my @res = $c->schema->storage->dbh->selectrow_array($sql, {}, 'local');
    my $body = $res[1];
    my $report = decode_json($body);
    my @report = @$report;
    my %regions_res;
    my @regions = $c->subsidiary->regions;
    for my $region (@regions) {
        next if $c->subsidiary->is_local($region);
        my @res_reg = $c->schema->storage->dbh->selectrow_array($sql, {}, $region);
        next unless @res_reg;
        my $dtreg   = $res_reg[0];
        my $bodyreg = $res_reg[1];
        my $json = decode_json($bodyreg);
        my @items = @{ $json->{report} };
        $body_reg->{$region} = encode_json(\@items);
        $dt_reg->{$region}   = $dtreg;
        my $url = $c->subsidiary->url($region);
        for my $item (@items) {
            $item->{region} = $item->{region} . " ($url)";
        }
        push @report, @items if @items;
    }
    return (\@report, $res[0], $body);
}

1;
