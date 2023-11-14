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

package MirrorCache::Task::MirrorFileCheck;
use Mojo::Base 'Mojolicious::Plugin';

use Mojo::UserAgent;

sub register {
    my ($self, $app) = @_;

    $app->minion->add_task(mirror_file_check => sub { _check($app, @_) });
}

sub _check {
    my ($app, $job, $path, $args) = (shift, shift, shift, ref $_[0] ? $_[0] : {@_});;
    return $job->fail('Empty path is not allowed') unless $path;

    my $minion = $app->minion;
    my $schema = $app->schema;

    # my $mirrors = $schema->resultset('Server')->search({country => 'de'});
    my @mirrors = $schema->resultset('Server')->search({ enabled => '1' });
    my ($countok, $counterr, $countoth) = (0, 0, 0);
    my $concurrency = 8;
    my $current = 0;
    $concurrency = @mirrors unless $concurrency < @mirrors;
    $job->note(_concurrency => $concurrency);

    for (my $i = 0; $i < $concurrency; $i++){
        my $m = shift @mirrors;
        next unless $m;
        my $id = $m->id;
        my $urldir = $m->urldir;
        $urldir = '/' unless $urldir;
        my $url = $m->hostname . $m->urldir . $path;
        # it looks that  defining $ua outside the loop greatly increases overal memory usage footprint for the task
        my $ua = Mojo::UserAgent->new->request_timeout(4)->connect_timeout(4);

        my ($next, $then, $catch);
        my $started = time();
        $current++;


        $next = sub {
            $m = shift;
            unless ($m) {
                $current--;
                unless ($current) {
                    Mojo::IOLoop->stop unless $current;
                }
                return;
            };
            $id = $m->id;
            my $urldir = $m->urldir;
            $urldir = '/' unless $urldir;
            $url = $m->hostname . $m->urldir . $path;
            $started = time();
            return $ua->head_p($url)->then($then, $catch);
        };

        $then = sub {
            my $tx = shift;
            my $elapsed = int(1000*(time() - $started));
            my $code = $tx->res->code;
            $job->note($m->hostname => $code . " ($elapsed ms) id=$id " . $tx->req->url);
            if ($code == 200) {
                $countok++;
            } elsif ($code > 399) {
                $counterr++;
            } else {
                $countoth++;
            }
            $next->(shift @mirrors);
        };

        $catch = sub {
            my $err = shift;
            my $elapsed = int(1000*(time() - $started));
            $job->note($m->hostname => $err . " ($elapsed ms) id=$id " . $url);
            $counterr++;
            $next->(shift @mirrors);
        };

        $ua->head_p($url)->then($then, $catch);
    }
    # sleep 5;

    Mojo::IOLoop->start;
    $job->note(_ok => $countok, _err => $counterr, _oth => $countoth);
    $job->finish;
}

1;
