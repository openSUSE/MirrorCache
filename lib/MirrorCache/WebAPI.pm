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

package MirrorCache::WebAPI;
use Mojo::Base 'Mojolicious';

use MirrorCache::Schema;

use Mojolicious::Commands;
use Mojo::Loader 'load_class';

use MirrorCache::Utils 'random_string';

# This method will run once at server start
sub startup {
    my $self = shift;
    my $root = $ENV{MIRRORCACHE_ROOT} || "";
    my $city_mmdb = $ENV{MIRRORCACHE_CITY_MMDB};
    die("MIRRORCACHE_CITY_MMDB is not a file ($city_mmdb)") if $city_mmdb && ! -f $city_mmdb;
    my $reader;

    MirrorCache::Schema->singleton;
    push @{$self->commands->namespaces}, 'MirrorCache::WebAPI::Command';
    $self->app->hook(before_server_start => sub {
        die("MIRRORCACHE_ROOT is not set") unless $root;
        if (-1 == rindex $root, 'http', 0) {
            die("MIRRORCACHE_ROOT is not a directory ($root)") unless -d $root;
        }

        # load auth module
        my $auth_method = $self->config->{auth}->{method} || "OpenID";
        my $auth_module = "MirrorCache::Auth::$auth_method";
        if (my $err = load_class $auth_module) {
            $err = 'Module not found' unless ref $err;
            die "Unable to load auth module $auth_module: $err";
        }
        $self->config->{_openid_secret} = random_string(16);

        # Optional initialization with access to the app
        my $r = $self->routes->namespaces(['MirrorCache::WebAPI::Controller']);
        $r->post('/session')->to('session#create');
        $r->delete('/session')->to('session#destroy');
        $r->get('/login')->name('login')->to('session#create');
        $r->post('/login')->to('session#create');
        $r->post('/logout')->name('logout')->to('session#destroy');
        $r->get('/logout')->to('session#destroy');
        $r->get('/response')->to('session#response');
        $r->post('/response')->to('session#response');

        my $rest = $r->any('/rest');
        my $rest_r    = $rest->any('/')->to(namespace => 'MirrorCache::WebAPI::Controller::Rest');
        $rest_r->get('/server')->name('rest_server')->to('table#list', table => 'Server');
        $rest_r->get('/server/:id')->to('table#list', table => 'Server');
        $rest_r->post('/server')->to('table#create', table => 'Server');
        $rest_r->post('/server/:id')->name('post_server')->to('table#update', table => 'Server');
        $rest_r->delete('/server/:id')->to('table#destroy', table => 'Server');
        $rest_r->put('/server/location/:id')->name('rest_put_server_location')->to('server_location#update_location');

        $rest_r->get('/folder')->name('rest_folder')->to('table#list', table => 'Folder');

        $rest_r->get('/folder_jobs/:id')->name('rest_folder_jobs')->to('folder_jobs#list');
        $rest_r->get('/myip')->name('rest_myip')->to('my_ip#show') if $reader;

        my $app_r = $r->any('/app')->to(namespace => 'MirrorCache::WebAPI::Controller::App');

        $app_r->get('/server')->name('server')->to('server#index');
        $app_r->get('/folder')->name('folder')->to('folder#index');
        $app_r->get('/folder/<id:num>')->name('folder_show')->to('folder#show');

        my $admin = $r->any('/admin');
        my $admin_auth;
        if ($ENV{MIRRORCACHE_TEST_TRUST_AUTH}) {
            $admin_auth = $admin->under('/')->name('ensure_admin');
        } else {
            $admin_auth = $admin->under('/')->to('session#ensure_admin')->name('ensure_admin');
        }

        # my $admin_r = $admin->to(namespace => 'MirrorCache::WebAPI::Controller::Admin')->any('/');
        my $admin_r = $admin_auth->any('/')->to(namespace => 'MirrorCache::WebAPI::Controller::Admin');

        $admin_r->delete('/folder/<id:num>')->to('folder#delete_cascade');
        $admin_r->delete('/folder_diff/<id:num>')->to('folder#delete_diff');
        
        $admin_r->get('/users')->name('get_users')->to('user#index');
        $admin_r->post('/user/:userid')->name('post_user')->to('user#update');

        my $rest_user_r = $admin_auth->any('/')->to(namespace => 'MirrorCache::WebAPI::Controller::Rest');
        $rest_user_r->delete('/user/<id:num>')->name('delete_user')->to('user#delete');

        $r->get('/index' => sub { shift->render('main/index') });
        $r->get('/' => sub { shift->render('main/index') })->name('index');

        $self->plugin(AssetPack => {pipes => [qw(Sass Css JavaScript Fetch Combine)]});
        $self->asset->process;
        $self->plugin('Dir');
    });


    $self->plugin('DefaultHelpers');
    $self->plugin('RenderFile');

    push @{$self->plugins->namespaces}, 'MirrorCache::WebAPI::Plugin';

    $self->plugin('Backstage');
    $self->plugin('AuditLog');
    $self->plugin('RenderFileFromMirror');
    $self->plugin('HashedParams');
    if ($city_mmdb) {
        require MaxMind::DB::Reader;
        $reader = MaxMind::DB::Reader->new( file => $city_mmdb );
    }
    $self->plugin('Mmdb', { reader => $reader });

    $self->plugin('Helpers', root => $root, route => '/download');
    if ($root) {
        # check prefix
        if (-1 == rindex $root, 'http', 0) {
            $self->plugin('RootLocal');
        } else {
            $self->plugin('RootRemote');
        }
    }
}

sub schema { MirrorCache::Schema->singleton }

sub run { __PACKAGE__->new->start }

1;
