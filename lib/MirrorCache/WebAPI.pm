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

use Mojolicious::Commands;

use MirrorCache::Schema;
use MirrorCache::Config;
use MirrorCache::Utils 'random_string';

has 'version';
has 'mcconfig';
has '_geodb';

sub new {
    my $self = shift->SUPER::new;
    # setting pid_file in startup will not help, need to set it earlier
    $self->config->{hypnotoad}{pid_file} = $ENV{MIRRORCACHE_HYPNOTOAD_PID} // '/run/mirrorcache/hypnotoad.pid';

    # I wasn't able to find reliable way in Mojolicious to detect when WebUI is started
    # (e.g. in daemon or hypnotoad in contrast to other commands like backend start / shoot)
    # so the code below tries to detect if _setup_ui is needed to be called

    my $started = 0;
    for (my $i = 0; my @r = caller($i); $i++) {
        next unless $r[3] =~ m/Hypnotoad/;
        $self->_setup_webui;
        $started = 1;
        last;
    }

    $self->hook(before_command => sub {
        my ($command, $arg) = @_;
        $self->_setup_webui if ref($command) =~ m/daemon|prefork/;
    }) unless $started;

    $self;
}

# This method will run once at server start
sub startup {
    my $self = shift;

    my $cfgfile = $ENV{MIRRORCACHE_INI};

    if ($cfgfile) {
        die "Cannot read config file: {$cfgfile}." unless -r $cfgfile;
    }

    my $config = MirrorCache::Config->new;
    $config->init($cfgfile) or die "Cannot initialize config file {$cfgfile}";
    $self->mcconfig($config);
    my $mcconfig = $self->mcconfig;
    my $root     = $mcconfig->root;

    my $geodb_file = $ENV{MIRRORCACHE_CITY_MMDB} || $ENV{MIRRORCACHE_IP2LOCATION};

    die("Geo IP location database is not a file ($geodb_file)\nPlease check MIRRORCACHE_CITY_MMDB or MIRRORCACHE_IP2LOCATION") if $geodb_file && ! -f $geodb_file;
    my $geodb;

    my $db_provider = $mcconfig->db_provider;

    eval {
        MirrorCache::Schema->connect_db     ($mcconfig->db_provider, $mcconfig->dsn,         $mcconfig->dbuser, $mcconfig->dbpass);
        MirrorCache::Schema->connect_replica($mcconfig->db_provider, $mcconfig->dsn_replica, $mcconfig->dbuser, $mcconfig->dbpass) if $mcconfig->dsn_replica;
        1;
    } or die("Database connect failed: $@");

    eval {
        MirrorCache::Schema->singleton->migrate($mcconfig->dbpass);
        1;
    } or die("Automatic migration failed: $@\nFix table structure and insert into mojo_migrations select 'mirrorcache', version");

    my $secret = random_string(16);
    $self->config->{hypnotoad}{listen}   = [$ENV{MOJO_LISTEN} // 'http://*:8080'];
    $self->config->{hypnotoad}{proxy}    = $ENV{MOJO_REVERSE_PROXY} // 0,
    $self->config->{hypnotoad}{workers}  = $ENV{MIRRORCACHE_WORKERS},
    # $self->config->{hypnotoad}{pid_file} = $ENV{MIRRORCACHE_HYPNOTOAD_PID}, - already set in constructor
    $self->config->{_openid_secret} = $secret;
    $self->secrets([$secret]);

    push @{$self->commands->namespaces}, 'MirrorCache::WebAPI::Command';

    $self->plugin('DefaultHelpers');
    my $current_version = $self->detect_current_version() || "unknown";
    $self->defaults(current_version => $current_version);
    $self->log->info("initializing $current_version");
    $self->version($current_version);

    $self->defaults(branding => $ENV{MIRRORCACHE_BRANDING});
    $self->defaults(custom_footer_message => $ENV{MIRRORCACHE_CUSTOM_FOOTER_MESSAGE});

    $self->plugin('RenderFile');

    push @{$self->plugins->namespaces}, 'MirrorCache::WebAPI::Plugin';

    $self->plugin('Backstage');
    $self->plugin('AuditLog');
    $self->plugin('RenderFileFromMirror');
    $self->plugin('HashedParams');

    if ($geodb_file && $geodb_file =~ /\.mmdb$/i) {
        require MaxMind::DB::Reader;
        $geodb = MaxMind::DB::Reader->new(file => $geodb_file);
        $self->plugin('Mmdb', { reader => $geodb });
    }
    elsif ($geodb_file && $geodb_file =~ /\.BIN$/i) {
        require Geo::IP2Location;
        $geodb = Geo::IP2Location->open($geodb_file);
        $self->plugin('Geolocation', { geodb => $geodb });
    }
    elsif ($geodb_file) {
        die("Unsupported geo IP location database ($geodb_file)\nPlease check MIRRORCACHE_CITY_MMDB or MIRRORCACHE_IP2LOCATION environment variables");
    }
    else {
        $self->plugin('Mmdb', { reader => $geodb });
    }
    $self->_geodb($geodb) if $geodb;

    $self->plugin('Helpers', root => $root, route => '/download');
    $self->plugin('Subsidiary');
    $self->plugin('Project');
    if ($root) {
        # check prefix
        if (-1 == rindex $root, 'http', 0) {
            $self->plugin('RootLocal');
        } else {
            $self->plugin('RootRemote');
        }
    }
}

sub _setup_webui {
    my $self = shift;
    my $root = $self->mcconfig->root;
    die("MIRRORCACHE_ROOT is not set") unless $root;
    if (-1 == rindex($root, 'http', 0)) {
        my $i = index($root, ':');
        my $dir = ($i > -1 ? substr($root, 0, $i) : $root);
        die("MIRRORCACHE_ROOT is not a directory ($root)") unless -d $dir;
    }

    # Optional initialization with access to the app
    my $r = $self->routes->namespaces(['MirrorCache::WebAPI::Controller']);
    $r->get('/favicon.ico' => sub { my $c = shift; $c->render_static('favicon.ico') });

    my $current_version = $self->version;
    $r->get('/version')->to(cb => sub {
        shift->render(text => $current_version);
    }) if $current_version;
    $r->post('/session')->to('session#create');
    $r->delete('/session')->to('session#destroy');
    $r->get('/login')->name('login')->to('session#create');
    $r->post('/login')->to('session#create');
    $r->post('/logout')->name('logout')->to('session#destroy');
    $r->get('/response')->to('session#response');
    $r->post('/response')->to('session#response');

    my $rest = $r->any('/rest');
    my $rest_r    = $rest->any('/')->to(namespace => 'MirrorCache::WebAPI::Controller::Rest');
    $rest_r->get('/server')->name('rest_server')->to('table#list', table => 'Server');
    $rest_r->get('/server/:id')->to('table#list', table => 'Server');
    $rest_r->get('/project')->to('project#list');
    $rest_r->get('/project/:name')->to('project#show');
    $rest_r->get('/project/:name/mirror_summary')->to('project#mirror_summary');
    $rest_r->get('/project/:name/mirror_list')->to('project#mirror_list');

    my $rest_operator_auth;
    $rest_operator_auth = $rest->under('/')->to('session#ensure_operator');
    my $rest_operator_r = $rest_operator_auth->any('/')->to(namespace => 'MirrorCache::WebAPI::Controller::Rest');
    $rest_operator_r->post('/server')->to('table#create', table => 'Server');
    $rest_operator_r->post('/server/:id')->name('post_server')->to('table#update', table => 'Server');
    $rest_operator_r->delete('/server/:id')->to('table#destroy', table => 'Server');
    $rest_operator_r->put('/server/location/:id')->name('rest_put_server_location')->to('server_location#update_location');
    $rest_operator_r->post('/sync_tree')->name('rest_post_sync_tree')->to('folder_jobs#sync_tree');

    $rest_r->get('/myserver')->name('rest_myserver')->to('table#list', table => 'MyServer');
    $rest_r->get('/myserver/:id')->to('table#list', table => 'MyServer');
    my $rest_usr_auth;
    $rest_usr_auth = $rest->under('/')->to('session#ensure_user');
    my $rest_usr_r = $rest_usr_auth->any('/')->to(namespace => 'MirrorCache::WebAPI::Controller::Rest');
    $rest_usr_r->post('/myserver')->to('table#create', table => 'MyServer');
    $rest_usr_r->post('/myserver/:id')->name('post_myserver')->to('table#update', table => 'MyServer');
    $rest_usr_r->delete('/myserver/:id')->to('table#destroy', table => 'MyServer');
    $rest_usr_r->put('/myserver/location/:id')->name('rest_put_myserver_location')->to('myserver_location#update_location');

    $rest_r->get('/folder')->name('rest_folder')->to('table#list', table => 'Folder');
    $rest_r->get('/repmirror')->name('rest_repmirror')->to('report_mirror#list');
    $rest_r->get('/repdownload')->name('rest_repdownload')->to('report_download#list');

    $rest_r->get('/folder_jobs/:id')->name('rest_folder_jobs')->to('folder_jobs#list');
    $rest_r->get('/myip')->name('rest_myip')->to('my_ip#show') if $self->_geodb;

    $rest_r->get('/stat')->name('rest_stat')->to('stat#list');
    $rest_r->get('/mystat')->name('rest_mystat')->to('stat#mylist');

    my $report_r = $r->any('/report')->to(namespace => 'MirrorCache::WebAPI::Controller::Report');
    $report_r->get('/mirror')->name('report_mirror')->to('mirror#index');
    $report_r->get('/mirrors')->name('report_mirrors')->to('mirrors#index');
    $report_r->get('/mirrors/:project')->name('report_mirrors_project')->to('mirrors#index');

    my $app_r = $r->any('/app')->to(namespace => 'MirrorCache::WebAPI::Controller::App');

    $app_r->get('/server')->name('server')->to('server#index');
    $app_r->get('/myserver')->name('myserver')->to('myserver#index');
    $app_r->get('/folder')->name('folder')->to('folder#index');
    $app_r->get('/folder/<id:num>')->name('folder_show')->to('folder#show');

    my $admin = $r->any('/admin');
    my $admin_auth = $admin->under('/')->to('session#ensure_admin')->name('ensure_admin');
    my $admin_r = $admin_auth->any('/')->to(namespace => 'MirrorCache::WebAPI::Controller::Admin');

    $self->plugin('Status' => { route => $admin->under('/status') }) if $self->mcconfig->plugin_status;

    $admin_r->delete('/folder/<id:num>')->to('folder#delete_cascade');
    $admin_r->delete('/folder_diff/<id:num>')->to('folder#delete_diff');

    $admin_r->get('/user')->name('get_user')->to('user#index');
    $admin_r->post('/user/:userid')->name('post_user')->to('user#update');

    my $rest_user_r = $admin_auth->any('/')->to(namespace => 'MirrorCache::WebAPI::Controller::Rest');
    $rest_user_r->delete('/user/<id:num>')->name('delete_user')->to('user#delete');

    $admin_r->get('/auditlog')->name('audit_log')->to('audit_log#index');
    $admin_r->get('/auditlog/ajax')->name('audit_ajax')->to('audit_log#ajax');

    $r->get('/index' => sub { shift->render('main/index') });
    $r->get('/' => sub { shift->render('main/index') })->name('index');

    $self->plugin(AssetPack => {pipes => [qw(Sass Css JavaScript Fetch Combine)]});
    $self->asset->process;
    $self->plugin('Stat');
    $self->plugin('Dir');
    $self->log->info("server started:  $current_version");
}

sub detect_current_version() {
    my $self = shift;
    eval {
        my $ver = `git rev-parse --short HEAD 2>/dev/null || :`;
        $ver = `rpm -q MirrorCache 2>/dev/null | grep -Po -- '[0-9]+\.[0-9a-f]+' | head -n 1 || :` unless $ver;
        $ver;
    } or $self->log->error('Cannot determine version');
}

sub schema { MirrorCache::Schema->singleton }

sub schemaR { MirrorCache::Schema->singletonR }

sub run { __PACKAGE__->new->start }

1;
