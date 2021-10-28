# Copyright (C) 2021 SUSE LLC
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
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

package MirrorCache::WebAPI::Plugin::Stat;
use Mojo::Base 'Mojolicious::Plugin', -signatures;

use Mojo::IOLoop;
use MirrorCache::Utils qw(datetime_now region_for_country);

has schema => undef, weak => 1;
has log    => undef, weak => 1;
has timer  => undef;

has rows => undef;

my $FLUSH_INTERVAL_SECONDS = $ENV{MIRRORCACHE_STAT_FLUSH_INTERVAL_SECONDS} // 10;
my $FLUSH_COUNT            = $ENV{MIRRORCACHE_STAT_FLUSH_COUNT} // 100;

sub register($self, $app, $args) {
    my $log = $app->log;
    $self->schema($app->schema);
    $self->log($app->log);

    $app->helper( 'stat' => sub {
        return $self;
    });
    1;
}

my $subsidiary_region = $ENV{MIRRORCACHE_REGION} // '';
$subsidiary_region = lc($subsidiary_region);


sub redirect_to_root($self, $dm, $not_miss = undef) {
    return $self->redirect_to_mirror(-5, $dm) if $dm->mirrorlist && $subsidiary_region && $dm->region ne $subsidiary_region;

    $not_miss = $dm->root_is_hit unless defined $not_miss;
    return $self->redirect_to_mirror(0, $dm) if ($not_miss);
    return $self->redirect_to_mirror(-1, $dm);
}

sub redirect_to_headquarter($self, $dm) {
    return $self->redirect_to_mirror(-2, $dm);
}

sub redirect_to_region($self, $dm) {
    return $self->redirect_to_mirror(-3, $dm);
}

sub redirect_to_mirror($self, $mirror_id, $dm) {
    my ($path, $trailing_slash) = $dm->path;
    return undef if $mirror_id == -1 && 'media' eq substr($path, -length('media'));
    $path = $dm->root_subtree . $path;
    my $rows = $self->rows;
    my @rows = defined $rows? @$rows : ();
    push @rows, [ $dm->ip_sha1, scalar $dm->agent, scalar ($path . $trailing_slash), $dm->country, datetime_now(), $mirror_id, $dm->folder_id, $dm->file_id, $dm->is_secure, $dm->is_ipv4, $dm->metalink? 1 : 0, $dm->mirrorlist? 1 : 0, $dm->is_head, $dm->file_age, $dm->folder_scan_last ];
    my $cnt = @rows;
    if ($cnt >= $FLUSH_COUNT) {
        $self->rows(undef);
        return $self->flush(\@rows);
    }
    $self->rows(\@rows);
    return if $self->timer;

    # my $loop = $self->ioloop;
    my $id = Mojo::IOLoop->singleton->timer($FLUSH_INTERVAL_SECONDS => sub ($loop) {
            $self->flush($self->rows);
        });
    Mojo::IOLoop->singleton->reactor->again($id);
    $self->timer($id);
}

my $RECKLESS=int($ENV{MIRRORCACHE_RECKLESS} // 0);

sub flush($self, $rows) {
    $self->timer(undef);
    return unless $rows;
    $self->rows(undef);
    my @rows = @$rows;
    my $sql = <<'END_SQL';
insert into stat(ip_sha1, agent, path, country, dt, mirror_id, folder_id, file_id, secure, ipv4, metalink, mirrorlist, head)
values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
END_SQL

    my %demand_sync;
    my %demand_scan;

    my ($dbh, $rs);
    eval {
        $self->schema->txn_do(sub {
            $dbh = $self->schema->storage->dbh;
            my $prep = $dbh->prepare($sql);
            for my $row (@rows) {
                my $folder_id  = $row->[6];
                my $mirror_id = $row->[5];
                my $file_age  = $row->[13];
                my $scan_last = $row->[14];
                pop @$row;
                pop @$row;
                $prep->execute(@$row);
                if ($folder_id) {
                    next if $mirror_id > 0;
                    next if $mirror_id < -1;
                    my $agent      = $row->[1];
                    next unless -1 == index($agent, 'bot');
                    my $file_id    = $row->[7];
                    next if $file_id && $file_id == -1;
                    if (!$file_id) {
                        $demand_sync{$folder_id} = 1;
                    } elsif ($RECKLESS) {
                        $demand_scan{$folder_id} = 1;
                    } else {
                        next unless $file_age && $scan_last;
                        $scan_last->set_time_zone('local');
                        my $scan_last_ago = time() - $scan_last->epoch;
                        if ($file_age < 3600) {
                            $demand_scan{$folder_id} = 1 unless $scan_last_ago < 30*60;
                        } elsif ($file_age < 4*3600) {
                            $demand_scan{$folder_id} = 1 unless $scan_last_ago < 60*60;
                        } elsif ($file_age < 24*3600) {
                            $demand_scan{$folder_id} = 1 unless $scan_last_ago < 4*60*60;
                        } elsif ($file_age < 72*3600) {
                            $demand_scan{$folder_id} = 1 unless $scan_last_ago < 8*60*60;
                        } else {
                            $demand_scan{$folder_id} = 1 unless $scan_last_ago < 24*60*60;
                        }
                    }
                }
            }
            1;
        });
    } or $self->log->error("[STAT] Error logging " . scalar(@rows) . " rows: " . $@);

    if (%demand_sync) {
        eval {
            $rs = $self->schema->resultset('Folder');
            $rs->request_sync_array(sort keys %demand_sync);
            1;
        } or $self->log->error("[STAT] Error requesting  sync for " . scalar(keys %demand_sync) . " rows: " . $@);
    }

    if (%demand_scan) {
        eval {
            $rs = $self->schema->resultset('Folder') unless $rs;
            $rs->request_scan_array(sort keys %demand_scan);
            1;
        } or $self->log->error("[STAT] Error requesting  scan for " . scalar(keys %demand_scan) . " rows: " . $@);
    }
}

1;
