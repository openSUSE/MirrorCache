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

# inspired by Mojolicious-Plugin-RenderFile
package MirrorCache::WebAPI::Plugin::RenderFileFromMirror;
use Mojo::Base 'Mojolicious::Plugin';

use strict;
use warnings;

use POSIX;
use XML::Writer;

use Mojo::File;
use Mojolicious::Static;
use Mojo::IOLoop::Subprocess;

sub register {
    my ($self, $app) = @_;

    $app->helper( 'mirrorcache.render_file' => sub {
        my ($c, $filepath)= @_;
        $c->emit_event('mc_dispatch', $filepath);
        my $root = $c->mc->root;
        my $f = Mojo::File->new($filepath);
        my $dirname  = $f->dirname;
        my $basename = $f->basename;
        my $dirname_basename = $dirname->basename;
        my $dm = $c->dm;
        return $root->render_file($c, $filepath, 1)
          if ( $dirname_basename eq "media.1"
            && !$dm->mirrorlist
            && (!$dm->metalink || $dm->metalink_accept)
            && $root->is_reachable);
        if ($dirname_basename eq "repodata" && !$dm->mirrorlist && !$dm->metalink) {
            # We don't redirect inside repodata, because if a mirror is outdated,
            # then zypper will have hard time working with outdated repomd.* files
            my $prefix = "repomd.xml";

            if (($prefix eq substr($basename,0,length($prefix))) && $root->is_reachable) {
                return $root->render_file($c, $filepath, 1);
            }
        }

        my $folder = $c->schema->resultset('Folder')->find({path => $dirname});
        my $file = $c->schema->resultset('File')->find_with_hash($folder->id, $basename) if $folder;
        my $country = $dm->country;
        my $region  = $dm->region;
        # render from root if we cannot determine country when GeoIP is enabled or unknown file
        if ((!$country && $ENV{MIRRORCACHE_CITY_MMDB}) || !$folder || !$file) {
            $c->mmdb->emit_miss($dirname, $country) unless $file;
            return $root->render_file($c, $filepath . '.metalink')  if ($dm->metalink && !$file); # file is unknown - cannot generate metalink
            return $root->render_file($c, $filepath)
              unless $dm->metalink # TODO we still can check file on mirrors even if it is missing in DB
              or $dm->mirrorlist;
        }

        my $scheme = 'http';
        $scheme = 'https' if $dm->is_secure;
        my $ipv = 'ipv4';
        $ipv = 'ipv6' unless $dm->is_ipv4;
        my $limit = $dm->mirrorlist ? 100 : 10;
        my ($mirrors_country, $mirrors_region, $mirrors_rest, @avoid_countries);
        $mirrors_country = $c->schema->resultset('Server')->mirrors_query(
            $country, $region,  $folder->id, $file->{id},          $scheme,
            $ipv,     $dm->lat, $dm->lng,    $dm->avoid_countries, $limit
        ) if $country;
        if ($region and ($dm->metalink or $dm->mirrorlist or !($mirrors_country && @$mirrors_country))) {
            @avoid_countries = @{$dm->avoid_countries} if $dm->avoid_countries;
            push @avoid_countries, $country if ($country and !(grep { $country eq $_ } @avoid_countries));
            $mirrors_region = $c->schema->resultset('Server')->mirrors_query(
                $country, $region,  $folder->id, $file->{id},       $scheme,
                $ipv,     $dm->lat, $dm->lng,    \@avoid_countries, $limit
            );
        }
        if ($dm->metalink or $dm->mirrorlist or !($mirrors_country && @$mirrors_country) && !($mirrors_region && @$mirrors_region)) {
            $mirrors_rest = $c->schema->resultset('Server')->mirrors_query(
                $country, $region,  $folder->id, $file->{id},          $scheme,
                $ipv,     $dm->lat, $dm->lng,    $dm->avoid_countries, $limit,  1
            );
        }

        my $mirror;
        if ($mirrors_country && @$mirrors_country) {
            $mirror = $mirrors_country->[0];
        }
        elsif ($mirrors_region && @$mirrors_region) {
            $mirror = $mirrors_region->[0];
        }
        elsif ($mirrors_rest && @$mirrors_rest) {
            $mirror = $mirrors_rest->[0];
        }

        if ($dm->metalink or $dm->mirrorlist) {
            if ($mirror) {
                $c->stat->redirect_to_mirror($mirror->{mirror_id});
                $c->emit_event('mc_mirror_miss', {path => $dirname, country => $country}) if $country && $country ne $mirror->{country};
            } else {
                $c->stat->redirect_to_root(0);
                $c->emit_event('mc_mirror_miss', {path => $dirname, country => $country}) if $country;
            }
        }

        if ($dm->metalink && !($dm->metalink_accept && 'media.1/media' eq substr($filepath,length($filepath)-length('media.1/media')))) {
            my $url = $c->req->url->to_abs;
            my $origin = $url->scheme . '://' . $url->host;
            my $xml    = _build_metalink(
                $dm, $folder->path, $file, $country, $region, $mirrors_country, $mirrors_region,
                $mirrors_rest, $origin, 'MirrorCache', $root->is_remote ? $root->location($c) : undef);
            $c->render(data => $xml, format => 'xml');
            return 1;
        }

        if ($dm->mirrorlist) {
            my $url    = $c->req->url->to_abs;
            my $origin = $url->scheme . '://' . $url->host;

            my $size = $file->{size};
            $size = MirrorCache::Utils::human_readable_size($size) if $size;
            my $mtime = $file->{mtime};
            $mtime = strftime("%d-%b-%Y %H:%M:%S", gmtime($mtime)) if $mtime;
            my $fileorigin = $root->is_remote ? $root->location($c) . $filepath : undef;

            my $filedata = {
                url   => $fileorigin,
                name  => $basename,
                size  => $size,
                mtime => $mtime,
            };

            my @mirrordata;
            if ($country and !$dm->avoid_countries || !(grep { $country eq $_ } $dm->avoid_countries)) {
                for my $m (@$mirrors_country) {
                    my $url = $m->{url};
                    push @mirrordata,
                      {
                        url        => $url . $filepath,
                        location   => uc($m->{country}),
                      };
                }
            }

            my @mirrordata_region;
            if ($region) {
                for my $m (@$mirrors_region) {
                    push @mirrordata_region,
                      {
                        url      => $m->{url} . $filepath,
                        location => uc($m->{country}),
                      };
                }
                @mirrordata_region = sort { $a->{url} cmp $b->{url} } @mirrordata_region;
            }

            my @mirrordata_rest;
            for my $m (@$mirrors_rest) {
                push @mirrordata_rest,
                  {
                    url      => $m->{url} . $filepath,
                    location => uc($m->{country}),
                  };
            }
            @mirrordata_rest = sort { $a->{url} cmp $b->{url} } @mirrordata_rest;

            $c->render(
                'mirrorlist',
                cur_path          => $filepath,
                file              => $filedata,
                mirrordata        => \@mirrordata,
                mirrordata_region => \@mirrordata_region,
                mirrordata_rest   => \@mirrordata_rest
            );
            return 1;
        }

        unless ($mirrors_country && @$mirrors_country) {
            $c->emit_event('mc_mirror_miss', {path => $dirname, country => $country}) if $country;
            $root->render_file($c, $filepath);
            return 1 if ($dm->root_country && $dm->root_country eq $country) or !($mirrors_region && @$mirrors_region) && !($mirrors_rest && @$mirrors_rest);
        }

        unless ($dm->pedantic) {
            # Check below is needed only when MIRRORCACHE_ROOT_COUNTRY is set
            # only with remote root and when no mirrors should be used for the root's country
            if ($country ne $mirror->{country} && $dm->root_is_better($mirror->{region}, $mirror->{lng})) {
                return $root->render_file($c, $filepath, 1);
            }
            my $url = $mirror->{url} . $filepath;
            $c->redirect_to($url);
            eval {
                $c->stat->redirect_to_mirror($mirror->{mirror_id});
                $c->emit_event('mc_mirror_miss', {path => $dirname, country => $country}) if $country && $country ne $mirror->{country};
            };
            return 1;
        }

        my $tx = $c->render_later->tx;
        my $ua  = Mojo::UserAgent->new;
        my $recurs1;
        my $expected_size = $file->{size};
        my $recurs = sub {
            my $prev = shift;

            return if $prev && ($prev == 200 || $prev == 302 || $prev == 301);
            my $mirror;
            if ($mirrors_country && @$mirrors_country) {
                $mirror = shift @$mirrors_country;
            }
            elsif ($mirrors_region && @$mirrors_region) {
                $mirror = shift @$mirrors_region;
            }
            elsif ($mirrors_rest && @$mirrors_rest) {
                $mirror = shift @$mirrors_rest;
            }
            unless ($mirror) {
                $c->emit_event('mc_mirror_miss', {path => $dirname, country => $country});
                return $root->render_file($c, $filepath);
            }
            # Check below is needed only when MIRRORCACHE_ROOT_COUNTRY is set
            # only with remote root and when no mirrors should be used for the root's country
            if ($country ne $mirror->{country} && $dm->root_is_better($mirror->{region}, $mirror->{lng})) {
                return $root->render_file($c, $filepath, 1);
            }
            my $url = $mirror->{url} . $filepath;
            my $code;
            $ua->head_p($url)->then(sub {
                my $result = shift->result;
                $code = $result->code;
                if ($code == 200 || $code == 302 || $code == 301) {
                    my $size = $result->headers->content_length if $result->headers;
                    if ($size && $expected_size && $size ne $expected_size) {
                        $code = 409;
                        return undef;
                    }
                    $c->redirect_to($url);
                    $c->emit_event('mc_path_hit', {path => $dirname, mirror => $url});
                    $c->emit_event('mc_mirror_miss', {path => $dirname, country => $country}) if $country && $country ne $mirror->{country};
                    $c->stat->redirect_to_mirror($mirror->{mirror_id});
                    return 1;
                }
                $c->emit_event('mc_mirror_path_error', {path => $dirname, code => $code, url => $url, server => $mirror->{id}, folder => $folder->id});
            })->catch(sub {
                $c->emit_event('mc_mirror_error', {path => $dirname, error => shift, url => $url, server => $mirror->{id}, folder => $folder->id});
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
        $mirrors_region, $mirrors_rest, $origin, $generator, $fileurl
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
    push @attribs, (origin => $origin) if $origin;
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

        my $colon = $fileurl ? index(substr($fileurl,0,6),':') : '';
        $writer->startTag('resources');
        {
            my $preference = 100;
            my $fullname = $path . '/' . $basename;
            my $root_included = 0;
            my $print_root = sub {
                return unless $fileurl;

                my $print = shift;
                return if $root_included and !$print;

                $writer->comment("File origin location: ") if $print;
                $writer->startTag('url', type => substr($fileurl,0,$colon), location => uc($dm->root_country), preference => $preference);
                $writer->characters($fileurl . $fullname);
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
                $writer->characters($url . $fullname);
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
                $writer->characters($url . $fullname);
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
                $writer->characters($url . $fullname);
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

1;
