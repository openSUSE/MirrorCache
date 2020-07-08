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

package MirrorCache::WebAPI::Plugin::AuditLog;
use Mojo::Base 'Mojolicious::Plugin';

use Mojo::IOLoop;
use Mojo::JSON 'to_json';
use MirrorCache::Events;

my @path_events = qw(path_miss path_hit path_scan_complete);
my @mirror_events = qw(mirror_pick mirror_probe mirror_scan_complete);
my @error_events = qw(best_mirror_error mirror_probe_error);
my @other_events = qw(debug);

sub register {
    my ($self, $app) = @_;

    # register for events
    my @events = (
        @path_events, @mirror_events, @error_events, @other_events
    );
    for my $e (@events) {
        MirrorCache::Events->singleton->on("mc_$e" => sub { shift; $self->on_event($app, @_) });
    }

    # log restart
    my $schema = $app->schema;
    $schema->resultset('AuditEvent')
      ->create({user_id => 0, name => 'startup', event_data => 'AuditLog registered'});
}

sub on_event {
    my ($self, $app, $args, $tag) = @_;
    my ($user_id, $event, $event_data) = @$args;
    # no need to log mc_ prefix in mc log
    $event =~ s/^mc_//;
    $app->schema->resultset('AuditEvent')->create({
            user_id       => $user_id,
            tag           => $tag,
            name          => $event,
            event_data    => to_json($event_data)});
}

1;
