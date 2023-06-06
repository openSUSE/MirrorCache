# Copyright (C) 2020-2022 SUSE LLC
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


# reasons for mirror_scan_error and mirror_path_error and mirror_error are similar
# mirror_scan_error means we were not able to find the file on the mirror, and we don't know if it ever existed
# mirror_path_error means we know that the file did exist on the mirror, but are not able to access it anymore, getting a valid HTML response code
# mirror_error means there was an error while trying to HEAD a file on a mirror (without valid HTML response)
# mirror_country_miss means that request was served by a mirror in region
my @error_events = qw(mirror_scan_error mirror_path_error mirror_error mirror_country_miss);
my @other_events = qw(unknown_ip debug);
my @user_events = qw(user_update user_delete server_create server_update server_delete myserver_create myserver_update myserver_delete);

my $last_error;

sub register {
    my ($self, $app) = @_;

    # register for events
    my @events = (
        @error_events, @other_events, @user_events
    );
    for my $e (@events) {
        MirrorCache::Events->singleton->on("mc_$e" => sub { shift; $self->on_event($app, @_) });
    }

    # log restart
    my $schema = $app->schema;
    eval {
        $schema->resultset('AuditEvent')
          ->create({user_id => -1, name => 'startup', event_data => "AuditLog registered $$"});
    } or do {
        if (!$last_error || 600 < time() - $last_error) {
            $app->log->error($app->dumper("Cannot register audit", $@));
            $last_error = time();
        }
    };
}

sub on_event {
    my ($self, $app, $args) = @_;
    my ($user_id, $event, $event_data) = @$args;
    my $tag;
    if (ref $event_data eq ref {} and exists $event_data->{tag}) {
        $tag = $event_data->{tag};
        delete($event_data->{tag});
    }

    # no need to log mc_ prefix in mc log
    $event =~ s/^mc_//;
    eval {
        $app->schema->resultset('AuditEvent')->create({
            user_id       => $user_id,
            tag           => $tag,
            name          => $event,
            event_data    => to_json($event_data)});
    } or do {
        if (!$last_error || 600 < time() - $last_error) {
            $app->log->error(Dumper("Cannot log audit", $@));
            $last_error = time();
        }
    };
}

1;
