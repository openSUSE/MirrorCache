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
# with this program; if not, see <http://www.gnu.org/licenses/>.

package MirrorCache::WebAPI::Controller::App::Server;
use Mojo::Base 'MirrorCache::WebAPI::Controller::App::Table';

sub index {
    my $c = shift;
    my $mirror_provider = $c->mcconfig->mirror_provider;
    if (my $url = $c->mcconfig->mirror_provider) {
        $url =~ s!^https?://(?:www\.)?!!i;
        $url =~ s!/.*!!;
        $url =~ s/[\?\#\:].*//;
        my $mirror_provider_url = 'https://' . $url . '/app/server';
        $c->stash( mirror_provider_url => $mirror_provider_url );
    }

    $c->SUPER::admintable('server');
}

sub update {
    my ($self) = @_;
    my $set  = $self->schema->resultset('Server');

    my $id = $self->param('id');

    my $mirror = $set->find($id);
    if (!$mirror) {
        $self->flash('error', "Can't find mirror {$id}");
    }
    else {
        $self->flash('info', 'Mirror ' . $mirror->hostname . ' updated');
        $self->emit_event('mc_mirror_updated', {hostname => $mirror->hostname});
    }

    $self->redirect_to($self->url_for('server'));
}

sub show {
    my $self = shift;
    my $hostname = $self->param('hostname');

    my $f = $self->schema->resultset('Server')->find_with_stability($hostname)
        or return $self->reply->not_found;

    my $admin_email = '';
    my $current_username = $self->current_username;
    my $is_owner = 0;
    $is_owner = 1 if ($current_username && $current_username eq ($f->{admin_username} // '' ));
    if ($self->is_operator || $self->is_admin || $is_owner) {
        $admin_email = $self->schema->storage->dbh->selectrow_array("SELECT msg FROM server_note WHERE hostname = ? AND kind = 'Email' ORDER BY dt DESC LIMIT 1", undef, $hostname);
    }
    my $subsidiary;
    if (my $regions = $self->mcconfig->regions) {
        if ($f->{region} && -1 == CORE::index($regions, $f->{region})) {
            $subsidiary = $self->subsidiary->url($f->{region});
        }
    }
    my $provider;
    if ($provider = $self->mcconfig->mirror_provider) {
        $provider =~ s!^https?://(?:www\.)?!!i;
        $provider =~ s!/.*!!;
        $provider =~ s/[\?\#\:].*//;
    }

    my $server = {
        id           => $f->{id},
        hostname     => $f->{hostname},
        public_notes => $f->{public_notes},
        admin_email  => $admin_email,
        subsidiary   => $subsidiary,
        provider     => $provider,
        rating_http  => $f->{rating_http},
        rating_https => $f->{rating_https},
        rating_ipv4  => $f->{rating_ipv4},
        rating_ipv6  => $f->{rating_ipv6},
        is_owner     => $is_owner,
    };

    return $self->render('app/server/show', server => $server);
}

1;
