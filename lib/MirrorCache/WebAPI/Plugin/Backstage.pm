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

use MirrorCache::Task::Report;

has app => undef, weak => 1;

my $DBPROVIDER;

sub new {
    my ( $class, $app ) = @_;
    my $self = $class->SUPER::new;
    return $self->app($app);
}

my @permanent_jobs =
    qw(folder_sync_schedule_from_misses folder_sync_schedule mirror_scan_schedule_from_misses mirror_scan_schedule_from_path_errors mirror_scan_schedule project_sync_schedule cleanup stat_agg_schedule mirror_check_from_stat report report_project_size_schedule);

sub register_tasks {
    my $self = shift;

    my $app = $self->app;
    if (defined $ENV{MIRRORCACHE_PERMANENT_JOBS}) {
        @permanent_jobs = split /[:,\s]+/, $ENV{MIRRORCACHE_PERMANENT_JOBS};
    }
    if ($app->mcconfig->mirror_provider) {
        push @permanent_jobs, 'mirror_provider_sync';
    }

    $app->plugin($_)
      for (
        qw(MirrorCache::Task::MirrorCheckFromStat),
        qw(MirrorCache::Task::MirrorFileCheck),
        qw(MirrorCache::Task::MirrorScanScheduleFromMisses),
        qw(MirrorCache::Task::MirrorScanScheduleFromPathErrors),
        qw(MirrorCache::Task::MirrorScanSchedule),
        qw(MirrorCache::Task::MirrorScan),
        qw(MirrorCache::Task::MirrorLocation),
        qw(MirrorCache::Task::MirrorProbe),
        qw(MirrorCache::Task::MirrorProviderSync),
        qw(MirrorCache::Task::FolderHashesCreate),
        qw(MirrorCache::Task::FolderHashesImport),
        qw(MirrorCache::Task::FolderSyncScheduleFromMisses),
        qw(MirrorCache::Task::FolderSyncSchedule),
        qw(MirrorCache::Task::FolderSync),
        qw(MirrorCache::Task::FolderPkgSync),
        qw(MirrorCache::Task::FolderTree),
        qw(MirrorCache::Task::ProjectSyncSchedule),
        qw(MirrorCache::Task::Cleanup),
        qw(MirrorCache::Task::Report),
        qw(MirrorCache::Task::ReportProjectSize),
        qw(MirrorCache::Task::ReportProjectSizeSchedule),
        qw(MirrorCache::Task::StatAggSchedule),
        qw(MirrorCache::Task::StatAggPkg),
      );
}

sub register {
    my ( $self, $app, $config ) = @_;

    $self->app($app) unless $self->app;
    my $schema = $app->schema;
    my $db = $schema->provider;
    $DBPROVIDER = lc($db);

eval {
    my $conn = "Mojo::$db"->new;
    $conn->dsn( $schema->dsn );
    if (my $user = $app->mcconfig->dbuser) {
        $conn->username($user);
    }
    if (my $pass = $app->mcconfig->dbpass) {
        $conn->password($pass);
    }

    $app->plugin( Minion => { $db => $conn } );
    $app->minion->backend->no_txn(1) if $db eq 'mysql';

    $self->register_tasks;
    1;
} or $app->log->error($@);
    # Enable the Minion Admin interface under /minion
    my $auth =
      $app->routes->under('/minion')->to('session#ensure_operator');
    $app->plugin( 'Minion::Admin' => { route => $auth } );

    # allow the continuously polled stats to be available on an
    # unauthenticated route to prevent recurring broken requests to the login
    # provider if not logged in
    my $route = $app->routes->find('minion_stats')->remove;
    $app->routes->any('/minion')->add_child($route);
    $route = $app->routes->find('minion_history')->remove;
    $app->routes->any('/minion')->add_child($route);

    my $backstage = MirrorCache::WebAPI::Plugin::Backstage->new($app);
    $app->helper( backstage => sub { $backstage } );

    $app->hook(
        before_server_start => sub {
            my $every = $ENV{MIRRORCACHE_PERMANENT_JOBS_CHECK_INTERVAL} // 5 * 60;
            $self->check_permanent_jobs;
            Mojo::IOLoop->next_tick(
                sub {
                    Mojo::IOLoop->recurring(
                        $every => sub {
                            $self->check_permanent_jobs;
                        }
                    );
                }
            );
        }
    ) if scalar @permanent_jobs;
}

sub check_permanent_jobs {
eval {
    my $app    = shift->app;
    my $minion = $app->minion;
    my $guard  = $minion->guard('check_permanent_jobs', 60);
    return undef unless $guard;

    my $jobs   = $minion->jobs(
        {
            tasks  => \@permanent_jobs,
            states => [ 'inactive', 'active' ]
        }
    );
    my $cnt          = 0;
    my %need_restart = map { $_ => 1 } @permanent_jobs;
    while ( my $info = $jobs->next ) {
        $cnt++;
        $app->log->error('Too many permanent jobs running')
          if $cnt == 10;
        return
          if $cnt > 100;    # prevent spawning too many jobs, shouldnot happen

        $need_restart{ $info->{task} } = 0;
    }

    # iterate by permanent_jobs to preserve original order
    for my $task ( @permanent_jobs ) {
        next unless $need_restart{$task};
        $app->log->warn("Haven't found running $task, starting it...");
        $minion->enqueue($task);
    }
};
}

sub inactive_jobs_exceed_limit {
    my ( $self, $limit, $task, $queue ) = @_;
    $limit = 200 unless $limit;
    $queue = 'default' unless $queue;
    my $db = $self->app->minion->backend->$DBPROVIDER->db;
    my $limit1 = $limit + 1;

    my $sql = <<'END_SQL';
select case when count(*) > ? then 1 else 0 end as exceed from (
select id
from minion_jobs
where state = 'inactive' and queue = ?
END_SQL
    my $res;
    $sql = "$sql and task = ?" if $task;
    $sql = "$sql limit ?) x";
    return $db->query($sql, $limit, $queue, $limit1)->expand->hash->{exceed} unless $task;
    return $db->query($sql, $limit, $queue, $task, $limit1)->expand->hash->{exceed};
}

sub enqueue {
    my $self = shift;
    my $task = shift;
    my @args = @_;
    my $app = $self->app;

    my %params;
    if ($task eq 'folder_sync') {
        $params{"notes"} = { $args[0] => 1 };
        if (my $queue = $app->mcproject->shard_for_path($args[0])) {
            $params{"queue"} = $queue;
        }
        $params{"priority"} = 2;
    } elsif ($task eq 'folder_tree') {
        if (my $queue = $app->mcproject->shard_for_path($args[0])) {
            $params{"queue"} = $queue;
        }
        $params{"priority"} = 10;
    }
    return $app->minion->enqueue($task => [@args] => \%params);
}

# raсe condition here souldn't be big issue
sub enqueue_unless_scheduled_with_parameter_or_limit {
    my ( $self, $task, $arg, $queue ) = @_;
    $queue = 'default' unless $queue;

    return 0 if $self->inactive_jobs_exceed_limit(300, $task, $queue);

    my $minion = $self->app->minion;
    my $res = $minion->backend->list_jobs(0, 1, {tasks => [$task], states => ['inactive','active'], notes => [$arg]});
    return -1 unless ( $res || !exists $res->{total} || $res->{total} > 0 );
    return $minion->enqueue($task => [($arg)] => {notes => { $arg => 1 }, queue => $queue, priority => 10});
}


1;

=encoding utf8

=head1 NAME

MirrorCache::WebAPI::Plugin::Backstage - The Minion job queue

=head1 SYNOPSIS

    $app->plugin('MirrorCache::WebAPI::Plugin::Backstage');

=head1 DESCRIPTION

L<MirrorCache::WebAPI::Plugin::Backstage> is the WebAPI job queue (and a tiny wrapper
around L<Minion>).

=cut
