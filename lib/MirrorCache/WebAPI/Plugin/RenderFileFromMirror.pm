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
use Mojo::File;
use Mojolicious::Static;
use Mojo::IOLoop::Subprocess;

sub register {
    my ($self, $app) = @_;
 
    $app->helper( 'mirrorcache.render_file' => sub {
   
        my ($c, $filepath) = @_;
        $c->emit_event('mc_dispatch', $filepath);
        my $mirror = "";
        my $f = Mojo::File->new($filepath);
        my $dirname  = $f->dirname;
        my $basename = $f->basename;
        if ($dirname->basename eq "repodata") {
            # We don't redirect inside repodata, because if a mirror is outdated, 
            # then zypper will have hard time working with outdated repomd.* files
            my $prefix = "repomd.xml";
            return $c->mc->root->render_file($c, $filepath) if $prefix eq substr($basename,0,length($prefix));
        }

        my $folder = $c->schema->resultset('Folder')->find({path => $dirname});
        my ($file, $country);
        $file = $c->schema->resultset('File')->find({folder_id => $folder->id, name => $basename}) if $folder;
        $country = $c->mmdb->country if $file;
        unless ($country) {
            $c->mmdb->emit_miss($dirname) unless $file;
            return $c->mc->root->render_file($c, $filepath); # TODO we still can check file on mirrors even if it is missing in DB
        }
        
        my $tx = $c->render_later->tx;
        my $scheme = 'http';
        $scheme = 'https' if $c->req->is_secure;
        my $ipv = 'ipv4';
        my $ip = $c->client_ip;
        $ipv = 'ipv6' if index($ip,':') > -1 && $ip ne '::ffff:127.0.0.1';
        my $mirrors = $c->schema->resultset('Server')->mirrors_country($country, $folder->id, $basename, $scheme, $ipv);
        my $ua  = Mojo::UserAgent->new;
        my $recurs1;
        my $recurs = sub {
            my $prev = shift;
            
            return if $prev && ($prev == 200 || $prev == 302 || $prev == 301);
            my $mirror = shift @$mirrors;
            unless ($mirror) {
                $c->emit_event('mc_mirror_miss', {path => $dirname, country => $country});
                return $c->mc->root->render_file($c, $filepath);
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

1;
