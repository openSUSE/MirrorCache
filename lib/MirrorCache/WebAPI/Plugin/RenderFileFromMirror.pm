# Copyright (C) 2020,2021 SUSE LLC
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

# inspired by Mojolicious-Plugin-RenderFile
package MirrorCache::WebAPI::Plugin::RenderFileFromMirror;
use Mojo::Base 'Mojolicious::Plugin';

use strict;
use warnings;

use POSIX;
use XML::Writer;
use DateTime;
use Mojo::File;
use Mojo::Date;
use Mojolicious::Static;
use Mojo::IOLoop::Subprocess;

sub register {
    my ($self, $app) = @_;
    $app->types->type(metalink => 'application/metalink+xml; charset=UTF-8');

    $app->helper( 'mirrorcache.render_file' => sub {
        my ($c, $filepath, $dm)= @_;
        my $root = $c->mc->root;
        my $f = Mojo::File->new($filepath);
        my $dirname = $f->dirname;
        my $realdirname = $root->realpath($f->dirname);
        $realdirname = $dirname unless $realdirname;
        my $basename = $f->basename;
        my $dirname_basename = $dirname->basename;
        my $subtree = $dm->root_subtree;
        return $root->render_file($dm, $filepath, 1) if $dm->must_render_from_root; # && $root->is_reachable;

        my $schema = $c->schema;
        my $folder = $schema->resultset('Folder')->find({path => $subtree . $dirname});
        my $folder_id;
        if ($folder) {
            $folder_id = $folder->id;
            $dm->folder_id($folder_id);
            $dm->folder_sync_last($folder->sync_last);
            $dm->folder_scan_last($folder->scan_last);
            my $need_update = 0;
            if (!$folder->wanted) {
                $need_update = 1;
            } else {
                my $diff = DateTime->now->subtract_datetime($folder->wanted->set_time_zone('local'));
                my $diff_days = $diff->in_units('days');
                $need_update = 1 if $diff_days > 13;
            }
            $schema->resultset('Folder')->set_wanted($folder_id) if $need_update;
        }
        my $realfolder_id;
        if ($realdirname ne $dirname) {
            my $realfolder = $schema->resultset('Folder')->find({path => $realdirname});
            $realfolder_id = $realfolder->id if $realfolder;
        }
        my $file = $schema->resultset('File')->find_with_hash(($realfolder_id? $realfolder_id : $folder_id), $basename) if $folder;
        if($file) {
            $dm->file_id($file->{id});
            $dm->file_age($file->{age});
        }
        my $country = $dm->country;
        my $region  = $dm->region;
        # render from root if we cannot determine country when GeoIP is enabled or unknown file
        if ((!$country && $ENV{MIRRORCACHE_CITY_MMDB}) || !$folder || !$file) {
            return $root->render_file($dm, $filepath . '.metalink')  if ($dm->metalink && !$file); # file is unknown - cannot generate metalink
            return $root->render_file($dm, $filepath)
              unless $dm->metalink # TODO we still can check file on mirrors even if it is missing in DB
              or $dm->mirrorlist;
        }

        if (!$folder || !$file) {
            return $c->render(status => 404, text => "File not found");
        }

        my (@mirrors_country, @mirrors_region, @mirrors_rest);

        _collect_mirrors($dm, \@mirrors_country, \@mirrors_region, \@mirrors_rest, $file->{id}, $folder_id);

        # add mirrors that have realpath
        _collect_mirrors($dm, \@mirrors_country, \@mirrors_region, \@mirrors_rest, $file->{id}, $realfolder_id) if $realfolder_id;
        my $mirror;
        $mirror = $mirrors_country[0] if @mirrors_country;
        $mirror = $mirrors_region[0]     if !$mirror && @mirrors_region;
        $mirror = $mirrors_rest[0]       if !$mirror && @mirrors_rest;

        if ($dm->metalink || $dm->mirrorlist) {
            if ($mirror) {
                $c->stat->redirect_to_mirror($mirror->{mirror_id}, $dm);
            } else {
                $c->stat->redirect_to_root($dm);
            }
        }

        if ($dm->metalink && !($dm->metalink_accept && 'media.1/media' eq substr($filepath,length($filepath)-length('media.1/media')))) {
            my $url = $c->req->url->to_abs;

            my $origin;
            if (my $publisher_url = $ENV{MIRRORCACHE_METALINK_PUBLISHER_URL}) {
                $publisher_url =~ s/^https?:\/\///;
                $origin = $url->scheme . '://' . $publisher_url;
            } else {
                $origin = $url->scheme . '://' . $url->host;
                $origin = $origin . ":" . $url->port if $url->port && $url->port != "80";
                $origin = $origin . $dm->route;
            }
            $origin = $origin . $filepath;
            my $xml    = _build_metalink(
                $dm, $folder->path, $file, $country, $region, \@mirrors_country, \@mirrors_region,
                \@mirrors_rest, $origin, 'MirrorCache', $root->is_remote ? $root->location($dm) : $root->redirect($dm, $folder->path) );
            $c->res->headers->content_disposition('attachment; filename="' .$basename. '.metalink"');
            $c->render(data => $xml, format => 'metalink');
            return 1;
        }

        if ($dm->mirrorlist) {
            my $url    = $c->req->url->to_abs;
            my @mirrordata;
            if ($country and !$dm->avoid_countries || !(grep { $country eq $_ } $dm->avoid_countries)) {
                for my $m (@mirrors_country) {
                    push @mirrordata,
                      {
                        url      => $m->{url},
                        location => uc($m->{country}),
                      };
                }
            }

            my @mirrordata_region;
            if ($region) {
                for my $m (@mirrors_region) {
                    push @mirrordata_region,
                      {
                        url      => $m->{url},
                        location => uc($m->{country}),
                      };
                }
                @mirrordata_region = sort { $a->{location} cmp $b->{location} || $a->{url} cmp $b->{url} } @mirrordata_region;
            }

            my @mirrordata_rest;
            for my $m (@mirrors_rest) {
                push @mirrordata_rest,
                  {
                    url      => $m->{url},
                    location => uc($m->{country}),
                  };
            }
            @mirrordata_rest = sort { $a->{location} cmp $b->{location} || $a->{url} cmp $b->{url} } @mirrordata_rest;
            return $c->render(json => {l1 => \@mirrordata, l2 => \@mirrordata_region, l3 => \@mirrordata_rest}) if ($dm->json);

            my $size = $file->{size};
            my $hsize = MirrorCache::Utils::human_readable_size($size) if defined $size;
            my $mtime = $file->{mtime};
            my $hmtime = strftime("%d-%b-%Y %H:%M:%S", gmtime($mtime)) if $mtime;
            my $fileorigin;
            my $fileoriginpath = $filepath;
            if ($root->is_remote) {
                $fileorigin = $root->location($dm);
            } else {
                my $redirect = $root->redirect($dm, $filepath);
                if ($redirect) {
                    $fileorigin = $redirect;
                    $fileoriginpath = $folder->path . '/' . $file->{name};
                } else {
                    $fileorigin = $url->scheme . '://' . $url->host;
                    $fileorigin = $fileorigin . ":" . $url->port if $url->port && $url->port != "80";
                    $fileorigin = $fileorigin . $dm->route;
                }
            }

            my $filedata = {
                url    => $fileorigin . $fileoriginpath,
                name   => $basename,
                size   => $size,
                hsize  => $hsize,
                mtime  => $mtime,
                hmtime => $hmtime,
                md5    => $file->{md5},
                sha1   => $file->{sha1},
                sha256 => $file->{sha256},
            };

            my @regions = $c->subsidiary->regions($region);
            $c->stash('nonavbar' => 1) if ($ENV{MIRRORCACHE_BRANDING});
            $c->stash('mirrorlist' => 1);
            my ($lat, $lng) = $dm->coord;
            $c->render(
                'mirrorlist',
                cur_path          => $filepath,
                file              => $filedata,
                mirrordata        => \@mirrordata,
                mirrordata_region => \@mirrordata_region,
                mirrordata_rest   => \@mirrordata_rest,
                country           => uc($country),
                region            => $region,
                ip                => $dm->ip,
                lat               => $lat,
                lng               => $lng,
                regions           => \@regions,
            );
            return 1;
        }
        unless ($mirror) {
            $root->render_file($dm, $filepath);
            return 1;
        }

        unless ($dm->pedantic) {
            # Check below is needed only when MIRRORCACHE_ROOT_COUNTRY is set
            # only with remote root and when no mirrors should be used for the root's country
            if ($country ne $mirror->{country} && $dm->root_is_better($mirror->{region}, $mirror->{lng})) {
                return $root->render_file($dm, $filepath, 1);
            }
            my $url = $mirror->{url};
            $c->redirect_to($url);
            eval {
                $c->stat->redirect_to_mirror($mirror->{mirror_id}, $dm);
            };
            return 1;
        }

        my $tx = $c->render_later->tx;
        my $ua  = Mojo::UserAgent->new->max_redirects(8);
        my $recurs1;
        my $expected_size  = $file->{size};
        my $expected_mtime = $file->{mtime};
        my $recurs = sub {
            my $prev = shift;

            return if $prev && ($prev == 200 || $prev == 302 || $prev == 301);
            my $mirror;
            if (@mirrors_country) {
                $mirror = shift @mirrors_country;
            }
            elsif (@mirrors_region) {
                $mirror = shift @mirrors_region;
            }
            elsif (@mirrors_rest) {
                $mirror = shift @mirrors_rest;
            }
            unless ($mirror) {
                return $root->render_file($dm, $filepath);
            }
            # Check below is needed only when MIRRORCACHE_ROOT_COUNTRY is set
            # only with remote root and when no mirrors should be used for the root's country
            if ($country ne $mirror->{country} && $dm->root_is_better($mirror->{region}, $mirror->{lng})) {
                $root->render_file($dm, $filepath, 1);
                return 1;
            }
            my $url = $mirror->{url};
            my $code;
            $ua->head_p($url, {'User-Agent' => 'MirrorCache/pedantic'})->then(sub {
                my $result = shift->result;
                $code = $result->code;
                if ($code == 200 || $code == 302 || $code == 301) {
                    my $size = $result->headers->content_length if $result->headers;
                    if ((defined $size && defined $expected_size) && ($size || $expected_size) && $size ne $expected_size) {
                        my $scan_last = $dm->folder_scan_last;
                        if ($scan_last && $expected_mtime && $expected_mtime < Mojo::Date->new($result->headers->last_modified)->epoch) {
                            if ($dm->scan_last_ago() > 15*60) {
                                $c->emit_event('mc_mirror_path_error', {e1 => $expected_mtime, e2 => Mojo::Date->new($result->headers->last_modified)->epoch, ago1 => $dm->scan_last_ago(), path => $dirname, code => $code, url => $url, folder => $folder->id, country => $dm->country, id => $mirror->{mirror_id}});
                            }
                            return $root->render_file($dm, $filepath, 0); # file on mirror is newer than we have
                        } elsif ($scan_last) {
                            if ($dm->scan_last_ago() > 24*60*60) {
                                $c->emit_event('mc_mirror_path_error', {ago2 => $dm->scan_last_ago(), path => $dirname, code => $code, url => $url, folder => $folder->id, country => $dm->country, id => $mirror->{mirror_id}});
                            }
                        } else {
                                $c->emit_event('mc_debug', {message => 'path error', path => $dirname, code => $code, url => $url, folder => $folder->id, country => $dm->country, id => $mirror->{mirror_id}});
                        }
                        $code = 409;
                        return undef;
                    }
                    $c->redirect_to($url);
                    $c->stat->redirect_to_mirror($mirror->{mirror_id}, $dm);
                    return 1;
                }
                if ($dm->sync_last_ago() > 4*60*60) {
                    $c->emit_event('mc_mirror_path_error', {path => $dirname, code => 200, url => $url, folder => $folder->id, country => $dm->country, id => $mirror->{mirror_id}});
                }
                if ($dm->scan_last_ago() > 4*60*60) {
                    $c->emit_event('mc_mirror_path_error', {path => $dirname, code => $code, url => $url, folder => $folder->id, country => $dm->country, id => $mirror->{mirror_id}});
                }
            })->catch(sub {
                $c->emit_event('mc_mirror_error', {path => $dirname, error => shift, url => $url, folder => $folder->id, id => $mirror->{mirror_id}});
            })->finally(sub {
                return $recurs1->($code);
                my $reftx = $tx;
            })->wait;
        };
        $recurs1 = $recurs;
        $recurs->();
    });

    return $app;
}

sub _build_metalink() {
    my (
        $dm,             $path,         $file,   $country,   $region, $mirrors_country,
        $mirrors_region, $mirrors_rest, $origin, $generator, $rooturl
    ) = @_;
    my $basename = $file->{name};
    $country = uc($country) if $country;
    $region  = uc($region)  if $region;

    my $publisher = $ENV{MIRRORCACHE_METALINK_PUBLISHER} || 'openSUSE';
    my $publisher_url = $ENV{MIRRORCACHE_METALINK_PUBLISHER_URL} || 'http://download.opensuse.org';

    my $writer = XML::Writer->new(OUTPUT => 'self', DATA_MODE => 1, DATA_INDENT => 2, );
    $writer->xmlDecl('UTF-8');
    my @attribs = (
        version => '3.0',
        xmlns => 'http://www.metalinker.org/',
        type => 'dynamic',
    );
    push @attribs, (origin => "$origin.metalink") if $origin;
    push @attribs, (generator => $generator) if $generator;
    push @attribs, (pubdate => strftime("%Y-%m-%d %H:%M:%S %Z", localtime time));

    $writer->startTag('metalink', @attribs);

    $writer->startTag('publisher');
    $writer->dataElement( name => $publisher    ) if $publisher;
    $writer->dataElement( url  => $publisher_url) if $publisher_url;
    $writer->endTag('publisher');

    $writer->startTag('files');
    {
        $writer->startTag('file', name => $basename);
        $writer->dataElement( size => $file->{size} ) if $file->{size};
        $writer->comment('<mtime>' . $file->{mtime} . '</mtime>') if ($file->{mtime});
        if (my $md5 = $file->{md5}) {
            $writer->startTag('hash', type => 'md5');
            $writer->characters($md5);
            $writer->endTag('hash');
        }
        if (my $sha1 = $file->{sha1}) {
            $writer->startTag('hash', type => 'sha-1');
            $writer->characters($sha1);
            $writer->endTag('hash');
        }
        if (my $sha256 = $file->{sha256}) {
            $writer->startTag('hash', type => 'sha-256');
            $writer->characters($sha256);
            $writer->endTag('hash');
        }
        if (my $piece_size = $file->{piece_size}) {
            $writer->startTag('pieces', length => $piece_size, type => 'sha-1');
            for my $piece (grep {$_} split /(.{40})/, $file->{pieces}) {
                $writer->dataElement( hash => $piece );
            }
            $writer->endTag('pieces');
        }

        my $colon = $rooturl ? index(substr($rooturl,0,6),':') : '';
        $writer->startTag('resources');
        {
            my $preference = 100;
            my $fullname = $path . '/' . $basename;
            my $root_included = 0;
            my $print_root = sub {
                return unless $rooturl;

                my $print = shift;
                return if $root_included and !$print;

                $writer->comment("File origin location: ") if $print;
                $writer->startTag('url', type => substr($rooturl,0,$colon), location => uc($dm->root_country), preference => $preference);
                $writer->characters($rooturl . $fullname);
                $writer->endTag('url');
                $root_included = 1;
                $preference--;
            };
            $writer->comment("Mirrors which handle this country ($country): ");
            for my $m (@$mirrors_country) {
                my $url = $m->{url};
                my $colon = index(substr($url,0,6), ':');
                next unless $colon > 0;

                $print_root->() if $country ne uc($m->{country}) && $dm->root_is_better($m->{region}, $m->{lng});
                $writer->startTag('url', type => substr($url,0,$colon), location => uc($m->{country}), preference => $preference);
                $writer->characters($url);
                $writer->endTag('url');
                $preference--;
            }
            $print_root->() if $dm->root_country eq lc($country);

            $writer->comment("Mirrors in the same continent ($region): ");
            for my $m (@$mirrors_region) {
                my $url   = $m->{url};
                my $colon = index(substr($url, 0, 6), ':');
                next unless $colon > 0;

                $print_root->() if $dm->root_is_better($m->{region}, $m->{lng});
                $writer->startTag(
                    'url',
                    type       => substr($url, 0, $colon),
                    location   => uc($m->{country}),
                    preference => $preference
                );
                $writer->characters($url);
                $writer->endTag('url');
                $preference--;
            }
            $print_root->() if $dm->root_is_hit;

            $writer->comment("Mirrors in other parts of the world: ");
            for my $m (@$mirrors_rest) {
                my $url   = $m->{url};
                my $colon = index(substr($url, 0, 6), ':');
                next unless $colon > 0;

                $print_root->() if $dm->root_is_better($m->{region}, $m->{lng});
                $writer->startTag(
                    'url',
                    type       => substr($url, 0, $colon),
                    location   => uc($m->{country}),
                    preference => $preference
                );
                $writer->characters($url);
                $writer->endTag('url');
                $preference--;
            }

            $print_root->(1);
        }
        $writer->endTag('resources');
        $writer->endTag('file');
    }
    $writer->endTag('files');
    $writer->endTag('metalink');

    return $writer->end();
}

sub _collect_mirrors {
    my ($dm, $mirrors_country, $mirrors_region, $mirrors_rest, $file_id, $folder_id) = @_;

    my $country = $dm->country;
    my $region  = $dm->region;
    my $scheme  = $dm->scheme;
    my $ipv = $dm->ipv;
    my $vpn = $dm->vpn;
    my ($lat, $lng) = $dm->coord;
    my $avoid_countries = $dm->avoid_countries;
    my $mirrorlist = $dm->mirrorlist;
    my $ipvstrict  = $dm->ipvstrict;
    my $metalink   = $dm->metalink;
    my $limit = $mirrorlist ? 100 : (( $metalink || $dm->pedantic )? 10 : 1);
    my $rs = $dm->c->schema->resultset('Server');

    my $m;
    $m = $rs->mirrors_query(
            $country, $region,  $folder_id, $file_id,        $scheme,
            $ipv,     $lat, $lng,    $avoid_countries, $limit,      0,
            !$mirrorlist, $ipvstrict, $vpn
    ) if $country;

    push @$mirrors_country, @$m if $m && scalar(@$m);
    my $found_count = scalar(@$mirrors_country) + scalar(@$mirrors_region) + scalar(@$mirrors_rest);

    if ($region && (($found_count < $limit))) {
        my @avoid_countries;
        push @avoid_countries, @$avoid_countries if $avoid_countries && scalar(@$avoid_countries);
        push @avoid_countries, $country if ($country and !(grep { $country eq $_ } @avoid_countries));
        $m = $rs->mirrors_query(
            $country, $region,  $folder_id, $file_id,       $scheme,
            $ipv,     $lat, $lng,    \@avoid_countries, $limit,     0,
            !$mirrorlist, $ipvstrict, $vpn
        );
        my $found_more = scalar(@$m) if $m;
        if ($found_more) {
            $found_count += $found_more;
            push @$mirrors_region, @$m;
        }
    }

    if (
        ($found_count < $limit && !$dm->root_country) ||
        ($metalink && $found_count < 3) ||
        $mirrorlist
    ) {
        $m = $rs->mirrors_query(
            $country, $region,  $folder_id, $file_id,          $scheme,
            $ipv,  $lat, $lng,    $avoid_countries, $limit,  1,
            !$mirrorlist, $ipvstrict, $vpn
        );
        my $found_more = scalar(@$m) if $m;
        if ($found_more) {
            $found_count += $found_more;
            push @$mirrors_rest, @$m;
        }
    }
    return $found_count;
}

1;
