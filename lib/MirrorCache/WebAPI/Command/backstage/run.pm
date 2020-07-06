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

package MirrorCache::WebAPI::Command::backstage::run;
use Mojo::Base 'Minion::Command::minion::worker';

use Mojo::Util 'getopt';

has description => 'Start Gru worker';
has usage       => sub { shift->extract_usage };

sub run {
    my ($self, @args) = @_;

    getopt \@args, 'o|oneshot' => \my $oneshot, 'reset-locks' => \my $reset_locks;

    my $minion = $self->app->minion;
    return $minion->perform_jobs if $oneshot;

    if ($reset_locks) {
        $self->app->log->info('Resetting all leftover Gru locks after restart');
        $minion->reset({locks => 1});
    }
    $self->SUPER::run(@args);
}

1;

=encoding utf8

=head1 NAME

MirrorCache::WebAPI::Command::backstage::run - Gru run command

=head1 SYNOPSIS

  Usage: APPLICATION backstage run [OPTIONS]

    script/openqa backstage run
    script/openqa backstage run -o

  Options:
    -o, --oneshot       Perform all currently enqueued jobs and then exit
        --reset-locks   Reset all remaining locks before startup

    See 'script/openqa backstage worker -h' for all available options.


=head1 DESCRIPTION

L<MirrorCache::WebAPI::Command::backstage::run> is a subclass of
L<Minion::Command::minion::worker> that adds Gru features with
L<MirrorCache::WebAPI::MinionJob>.

=cut
