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

# a lot of this is inspired (and even in parts copied) from Minion (Artistic-2.0)
package MirrorCache::WebAPI::Plugin::Backstage;
use Mojo::Base 'Mojolicious::Plugin';

use Minion;
use DBIx::Class::Timestamps 'now';
use MirrorCache::Schema;
# use MirrorCache::WebAPI::MinionJob;
# use MirrorCache::Log 'log_info';
use Mojo::Pg;

has app => undef, weak => 1;
has 'dsn';

sub new {
    my ($class, $app) = @_;
    my $self = $class->SUPER::new;
    return $self->app($app);
}

sub register_tasks {
    my $self = shift;

    my $app = $self->app;
    $app->plugin($_)
      for (
        # qw(MirrorCache::Task::AuditEvents::Limit), # TODO task for deleting old audit events
        qw(MirrorCache::Task::MirrorScanScheduleFromMisses),
        qw(MirrorCache::Task::MirrorScan),
      );
}

sub register {
    my ($self, $app, $config) = @_;

    $self->app($app) unless $self->app;
    my $schema = $app->schema;

    my $conn = Mojo::Pg->new;
    if (ref $schema->storage->connect_info->[0] eq 'HASH') {
        $self->dsn($schema->dsn);
        $conn->username($schema->storage->connect_info->[0]->{user});
        $conn->password($schema->storage->connect_info->[0]->{password});
    }
    else {
        $self->dsn($schema->storage->connect_info->[0]);
    }
    $conn->dsn($self->dsn());

    # # set the search path in accordance with the test setup done in MirrorCache::Test::Database
    # if (my $search_path = $schema->search_path_for_tests) {
    #     log_info("setting database search path to $search_path when registering Minion plugin\n");
    #     $conn->search_path([$search_path]);
    # }

    $app->plugin(Minion => {Pg => $conn});

    # # We use a custom job class (for legacy reasons)
    # $app->minion->on(
    #    worker => sub {
    #        my ($minion, $worker) = @_;
    #        $worker->on(
    #            dequeue => sub {
    #                my ($worker, $job) = @_;

    #                # Reblessing the job is fine for now, but in the future it would be nice
    #                # to use a role instead
    #                bless $job, 'MirrorCache::WebAPI::MinionJob';
    #            });
    #    });

    $self->register_tasks;

    # Enable the Minion Admin interface under /minion
    my $auth = $app->routes->under('/minion'); # ->to('session#ensure_admin'); TODO only authorized users
    $app->plugin('Minion::Admin' => {route => $auth});

    my $backstage = MirrorCache::WebAPI::Plugin::Backstage->new($app);
    $app->helper(backstage => sub { $backstage });
}

# counts the number of jobs for a certain task in the specified states
sub count_jobs {
    my ($self, $task, $states) = @_;
    my $res = $self->app->minion->backend->list_jobs(0, undef, {tasks => [$task], states => $states});
    return ($res && exists $res->{total}) ? $res->{total} : 0;
}

1;

=encoding utf8

=head1 NAME

MirrorCache::WebAPI::Plugin::Minion - The Minion job queue

=head1 SYNOPSIS

    $app->plugin('MirrorCache::WebAPI::Plugin::Minion');

=head1 DESCRIPTION

L<MirrorCache::WebAPI::Plugin::Minion> is the WebAPI job queue (and a tiny wrapper
around L<Minion>).

=cut
