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
        my $mirror = "";
        my $f = Mojo::File->new($filepath);
        my $dirname  = $f->dirname;
        my $basename = $f->basename;
        if ($dirname->basename eq "repodata") {
            # We don't redirect inside repodata, because if a mirror is outdated, 
            # then zypper will have hard time working with outdated repomd.* files
            my $prefix = "repomd.xml";
            
            if (($prefix eq substr($basename,0,length($prefix))) && $root->is_reachable) {
                return $root->render_file($c, $filepath);
            }
        }

        my $folder = $c->schema->resultset('Folder')->find({path => $dirname});
        my $file = $c->schema->resultset('File')->find({folder_id => $folder->id, name => $basename}) if $folder;
        my $dm = $c->dm;
        my $country = $dm->country;
        # render from root if we cannot determine country when GeoIP is enabled or unknown file
        if ((!$country && $ENV{MIRRORCACHE_CITY_MMDB}) || !$folder || !$file) {
            $c->mmdb->emit_miss($dirname) unless $file;
            return $root->render_file($c, $filepath); # TODO we still can check file on mirrors even if it is missing in DB
        }

        my $tx = $c->render_later->tx;
        my $scheme = 'http';
        $scheme = 'https' if $c->req->is_secure;
        my $ipv = 'ipv4';
        my $ip = $dm->ip;
        $ipv = 'ipv6' if index($ip,':') > -1 && $ip ne '::ffff:127.0.0.1';
        my $mirrors = $c->schema->resultset('Server')->mirrors_country($country, $folder->id, $file->id, $scheme, $ipv, $dm->lat, $dm->lng);

        my $headers = $c->req->headers;
        my $accept;
        $accept = $headers->accept if $headers;
        if ($accept && $accept ne '*/*' && $basename ne 'media') {
            if ($accept =~ m/\bapplication\/metalink/ && $country) {
                my $url = $c->req->url->to_abs;
                my $origin = $url->scheme . '://' . $url->host;
                my $xml = _build_metalink($folder->path, $basename, 0, $country, $mirrors, $origin, 'MirrorCache');
                return $c->render(data => $xml, format => 'xml');
            }
        }
        my $ua  = Mojo::UserAgent->new;
        my $recurs1;
        my $recurs = sub {
            my $prev = shift;

            return if $prev && ($prev == 200 || $prev == 302 || $prev == 301);
            my $mirror = shift @$mirrors;
            unless ($mirror) {
                $c->emit_event('mc_mirror_miss', {path => $dirname, country => $country});
                return $root->render_file($c, $filepath);
            }
            my $url = $mirror->{url} . $filepath;
            my $code;
            $ua->head_p($url)->then(sub {
                $code = shift->result->code;
                if ($code == 200 || $code == 302 || $code == 301) {
                    $c->emit_event('mc_path_hit', {path => $dirname, mirror => $url});
                    return $c->redirect_to($url);
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
    my ($path, $basename, $size, $country, $mirrors, $origin, $generator) = @_;
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
        $writer->startTag('resources');
        {
            $writer->comment("Mirrors which handle this country ($country): ");
            my $preference = 100;
            my $fullname = $path . '/' . $basename;
            for my $m (@mirrors) {
                my $url = $m->{url};
                my $colon = index(substr($url,0,6), ':');
                next unless $colon > 0;

                $writer->startTag('url', type => substr($url,0,$colon), location => $country, preference => $preference);
                $writer->characters($url . $fullname);
                $writer->endTag('url');
                $preference--;

            }
        }
        $writer->endTag('resources');
        $writer->endTag('file');
    }
    $writer->endTag('files');
    $writer->endTag('metalink');

    return $writer->end();
}

1;
