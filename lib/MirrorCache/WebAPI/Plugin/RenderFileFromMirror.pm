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
        if ($dirname->basename eq "repodata") {
            # We don't redirect inside repodata, because if a mirror is outdated, 
            # then zypper will have hard time working with outdated repomd.* files
            my $prefix = "repomd.xml";

            if (($prefix eq substr($basename,0,length($prefix))) && $root->is_reachable) {
                return $root->render_file($c, $filepath, 1);
            }
        }

        my $folder = $c->schema->resultset('Folder')->find({path => $dirname});
        my $file = $c->schema->resultset('File')->find({folder_id => $folder->id, name => $basename}) if $folder;
        my $dm = $c->dm;
        my $country = $dm->country;
        my $region  = $dm->region;
        # render from root if we cannot determine country when GeoIP is enabled or unknown file
        if ((!$country && $ENV{MIRRORCACHE_CITY_MMDB}) || !$folder || !$file) {
            $c->mmdb->emit_miss($dirname, $country) unless $file;
            return $root->render_file($c, $filepath . '.metalink')  if ($dm->metalink && !$file); # file is unknown - cannot generate metalink
            return $root->render_file($c, $filepath) unless $dm->metalink; # TODO we still can check file on mirrors even if it is missing in DB
        }

        my $scheme = 'http';
        $scheme = 'https' if $dm->is_secure;
        my $ipv = 'ipv4';
        $ipv = 'ipv6' unless $dm->is_ipv4;
        my $ip = $dm->ip;
        my $mirrors = $c->schema->resultset('Server')->mirrors_country($country, $region, $folder->id, $file->id, $scheme, $ipv, $dm->lat, $dm->lng, $dm->avoid_countries);
        unless (@$mirrors) {
            $c->emit_event('mc_mirror_miss', {path => $dirname, country => $country});
            return $root->render_file($c, $filepath) unless $dm->metalink;
        }

        if ($dm->metalink && !($dm->metalink_accept && 'media.1/media' eq substr($filepath,length($filepath)-length('media.1/media')))) {
            my $url = $c->req->url->to_abs;
            my $origin = $url->scheme . '://' . $url->host;
            my $xml = _build_metalink($dm, $folder->path, $basename, $file->size, $file->mtime, $country, $mirrors, $origin, 'MirrorCache', $root->is_remote? $root->location($c) : undef);
            $c->render(data => $xml, format => 'xml');
            if ($mirrors && @$mirrors) {
                $c->stat->redirect_to_mirror($mirrors->[0]->{mirror_id});
                $c->emit_event('mc_mirror_miss', {path => $dirname, country => $country}) if $country && $country ne $mirrors->[0]->{country};
            } else {
                $c->stat->redirect_to_root;
            }
            return 1;
        }
        my $tx = $c->render_later->tx;
        my $ua  = Mojo::UserAgent->new;
        my $recurs1;
        my $expected_size = $file->size;
        my $recurs = sub {
            my $prev = shift;

            return if $prev && ($prev == 200 || $prev == 302 || $prev == 301);
            my $mirror = shift @$mirrors;
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
    my ($dm, $path, $basename, $size, $mtime, $country, $mirrors, $origin, $generator, $fileurl) = @_;
    $country = uc($country) if $country;
    my @mirrors = @$mirrors;
    my $mirror_count = @mirrors;

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
    if ($publisher) {
        $writer->startTag('name');
        $writer->characters($publisher);
        $writer->endTag('name');
    }

    if ($publisher_url) {
        $writer->startTag('url');
        $writer->characters($publisher_url);
        $writer->endTag('url');
    }
    $writer->endTag('publisher');

    $writer->startTag('files');
    {
        $writer->startTag('file', name => $basename);
        if ($size) {
            $writer->startTag('size');
            $writer->characters($size);
            $writer->endTag('size');
        }
        $writer->comment("<mtime>$mtime</mtime>") if ($mtime);
        my $colon = $fileurl ? index(substr($fileurl,0,6),':') : '';
        $writer->startTag('resources');
        {
            $writer->comment("Mirrors which handle this country ($country): ");
            my $preference = 100;
            my $fullname = $path . '/' . $basename;
            my $root_included = 0;
            my $print_root = sub {
                return unless $fileurl;
                $writer->comment("File origin location: ") if shift;
                $writer->startTag('url', type => substr($fileurl,0,$colon), location => uc($dm->root_country), preference => $preference);
                $writer->characters($fileurl . $fullname);
                $writer->endTag('url');
                $preference--;
            };
            for my $m (@mirrors) {
                my $url = $m->{url};
                my $colon = index(substr($url,0,6), ':');
                next unless $colon > 0;
                if (!$root_included && $country ne $m->{country} && $dm->root_is_better($m->{region}, $m->{lng})) {
                    $root_included = 1;
                    $print_root->();
                }

                $writer->startTag('url', type => substr($url,0,$colon), location => uc($m->{country}), preference => $preference);
                $writer->characters($url . $fullname);
                $writer->endTag('url');
                $preference--;

            }
            $print_root->() if !$root_included && $dm->root_country;
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
