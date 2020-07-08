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

use Data::Dumper;

sub register {
    my ($self, $app, $args) = @_;

    my $root = $args->{root};
    push @{$app->static->paths}, $root;
 
    $app->helper( 'mirrorcache.render_file' => sub {
        my ($c, $filepath, $route) = @_;
   
        my $mirror = "";
        eval {
            # my $ip = $c->get_client_ip();
            my $ip = '';
            $mirror = $c->mirrorcache->best_mirror( $ip, $filepath );
            1;
        } or $c->emit_event('mc_best_mirror_error', {path => $filepath, err => $@});

        return $c->redirect_to($mirror) if $mirror;
        my $res = $c->reply->static($filepath);
        return !!$res;
    });

    $app->helper( 'mirrorcache.best_mirror' => sub {
        my ($c, $ip, $filepath) = @_;
        my $f = Mojo::File->new($filepath);
    
        my $dirname = $f->dirname;
        my $mirrors = $c->schema->resultset('Server')->mirrors_country($c->mmdb->country(), $dirname, $f->basename);
        my $ua  = Mojo::UserAgent->new;

        for my $mirrorhash (@$mirrors) {
            my $mirror = $mirrorhash->{url};
            my $ok = 0;
            my $err = 'Timeout';
            # Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
            # $ua->head_p($mirror . $filepath)->then(sub {
            #    my $tx = shift;
            #    print(STDERR "res\n");
            #    print(STDERR 'res ' . $tx->result->code . "\n");
            #    $ok = 1 unless ($tx->result->code < 200 or $tx->result->code > 299);
            # })->catch(sub {
            #    my $err1 = shift;
            #    print(STDERR "catch $err1\n");
            #    $err = $err1;
            # })->timeout(1 => 'Timeout!')->wait;
            # })->wait;
            my $tx = $ua->head($mirror . $filepath);
            $ok = 1 unless ($tx->result->code < 200 or $tx->result->code > 299);

            if ($ok) {
                $c->emit_event('mc_mirror_probe', {mirror => $mirror, tag => 0});
                $c->emit_event('mc_mirror_pick', {mirror => $mirror});
                $c->emit_event('mc_path_hit', {path => $dirname, mirror => $mirror});
                return $mirror;
            } else {
                $c->emit_event('mc_mirror_probe', {mirror => $mirror, error => $err, tag => 1});
            }
        }

        $c->emit_event('mc_path_miss', $dirname);
        return undef;
    });
    return $app;
}

1;
