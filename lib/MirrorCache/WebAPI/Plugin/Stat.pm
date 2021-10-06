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
use MirrorCache::Utils 'datetime_now';
use Data::Dumper;

# has ioloop => sub { Mojo::IOLoop->new };

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
    push @rows, [ $dm->ip_sha1, scalar $dm->agent, scalar ($path . $trailing_slash), $dm->country, datetime_now(), $mirror_id, $dm->folder_id, $dm->file_id, $dm->is_secure, $dm->is_ipv4, $dm->metalink? 1 : 0, $dm->mirrorlist? 1 : 0, $dm->is_head ];
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

sub flush($self, $rows) {
    $self->timer(undef);
    return unless $rows;
    $self->rows(undef);
    my @rows = @$rows;
    my $sql = <<'END_SQL';
insert into stat(ip_sha1, agent, path, country, dt, mirror_id, folder_id, file_id, secure, ipv4, metalink, mirrorlist, head)
values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
END_SQL

    my %demand;

    eval {
        $self->schema->txn_do(sub {
            my $dbh = $self->schema->storage->dbh;
            my $prep = $dbh->prepare($sql);
            for my $row (@rows) {
                $prep->execute(@$row);
                my $folder_id = $row->[6];
                my $country   = $row->[3];
                $demand{$folder_id}{$country} = 1 if $folder_id && $country;
            }

            my @k = keys %demand;
            if (@k) {
                my $rs = $self->schema->resultset('Folder');
                foreach my $folder_id (sort @k) {
                    foreach my $country (sort keys %{ $demand{$folder_id} }) {
                        $rs->request_for_country($folder_id, $country);
                    }
                }
            }
            1;
        });
    } or $self->log->error("[STAT] Error logging " . scalar(@rows) . " rows: " . $@);
}

1;
