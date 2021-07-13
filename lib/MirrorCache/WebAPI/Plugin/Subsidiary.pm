# Copyright (C) 2021 SUSE LLC
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
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

package MirrorCache::WebAPI::Plugin::Subsidiary;
use Mojo::Base 'Mojolicious::Plugin';

my $headquarter_url;
my $subsidiary_region;

my $subsidiaries_initialized = 0;
my %subsidiary_urls;
my @regions;

sub register {
    my ($self, $app) = @_;
    my @subsidiaries;
    # having both MIRRORCACHE_HEADQUARTER and MIRRORCACHE_REGION means that we are Subsidiary
    if ($ENV{MIRRORCACHE_HEADQUARTER} && $ENV{MIRRORCACHE_REGION}) {
        $subsidiary_region = lc($ENV{MIRRORCACHE_REGION});
        $headquarter_url   = $ENV{MIRRORCACHE_HEADQUARTER};

        $app->helper('subsidiary.has'     => sub { return undef; });
        $app->helper('subsidiary.regions' => sub { return undef; });
        $app->helper('subsidiary.redirect_headquarter' => sub {
            my ($self, $region) = @_;
            # redirect to the headquarter if country is not our region
            return $headquarter_url if $region && $subsidiary_region ne lc($region);
            return undef;
        });
    } else {
        eval { #the table may be missing - no big deal
            @subsidiaries = $app->schema->resultset('Subsidiary')->all;
        };
        for my $s (@subsidiaries) {
            my $url = $s->hostname;
            $url = "http://" . $url unless 'http' eq substr($url, 0, 4);
            $url = $url . $s->uri if $s->uri;
            my $region = lc($s->region);
            next unless $region;
            push @regions, $region;
            my $obj = Mojo::URL->new($url)->to_abs;
            $subsidiary_urls{$region} = $obj;

            $app->routes->get("/rest/$region" => sub {
                my $c = shift;
                my $file = $c->param('file');
                return $c->render(code => 400) unless $file;
                my $req = $obj->clone;
                $req->scheme($c->req->url->to_abs->scheme);
                $req->path($req->path . $file);
                $req->query('mirrorlist&json');
                $c->proxy->get_p($req);
            });
         }

         $app->helper('subsidiary.has'     => \&_has_subsidiary);
         $app->helper('subsidiary.regions' => \&_regions);
         $app->helper('subsidiary.redirect_headquarter' => sub { return undef; });
    }
    $app->helper('subsidiary.headquarter_url' => sub { return $headquarter_url; });
    return $self;
}

sub _has_subsidiary {
    return undef unless keys %subsidiary_urls;
    my ($self, $region, $origin_url) = @_;
    my $region_url = $subsidiary_urls{$region};
    return $region_url unless $region_url && $origin_url;
    my $url = $origin_url->to_abs->clone;
    $url->host($region_url->host);
    $url->port($region_url->port);
    $url->path_query($region_url->path . $url->path_query) if ($region_url->path);
    return $url;
}

# return url for all subsidiaries
sub _regions {
    return undef unless keys %subsidiary_urls;
    my ($self, $region) = @_;
    my $url = $subsidiary_urls{$region};
    my @res = ($url? $region : '');

    for my $s (@regions) {
        next if $region eq $s;
        push @res, $s;
    }

    return @res;
}

1;
