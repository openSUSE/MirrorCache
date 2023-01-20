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

package MirrorCache::Task::MirrorProviderSync;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::JSON qw(decode_json);
use MirrorCache::Utils 'datetime_now';

sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(mirror_provider_sync => sub { _run($app, @_) });
}

my $DELAY = int($ENV{MIRRORCACHE_MIRROR_PROVIDER_SYNC_RETRY_INTERVAL} // 10 * 60);

sub _run {
    my ($app, $job, $once) = @_;
    my $minion = $app->minion;

    return $job->finish('No mirror provider configured')
        unless my $mirror_provider = $app->mcconfig->mirror_provider;

    return $job->finish('Previous job is still active')
        unless my $guard = $minion->guard('mirror_provider_sync', 300);

    # getting list of mirrors to sync
    my $ua = Mojo::UserAgent->new->max_redirects(10);

    my $url = $mirror_provider;
    my $got = $ua->get($url)->result;

    return $job->fail('Request to MIRROR_PROVIDER ' . $url . ' failed, response code ' . $got->code)
        if $got->code > 299;

    my $server_list = $got->json;

    return $job->fail('Failed to interpret json as array in MIRROR_PROVIDER request:' . $url)
        unless ref $server_list eq 'ARRAY' && @$server_list;

    my $schema = $app->schema;
    my $rsServer = $schema->resultset('Server');

    for my $server (@$server_list) {
        next unless $server->{hostname} && $server->{id};

        my $fail = 1;
        my $res = $rsServer->check_sync($server);
        unless ($res) {
            $job->note($server->{hostname} => 'Failed to sync ' . datetime_now) ;
        } elsif ($res > 1) {
            $job->note($server->{hostname} => 'Synced ' . datetime_now) ;
        }
    }

    return $job->retry({delay => $DELAY}) unless $once;
}

1;
