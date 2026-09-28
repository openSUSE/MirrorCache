# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -signatures;

BEGIN {
    $ENV{MIRRORCACHE_ROOT} = 'http://localhost';
    $ENV{MIRRORCACHE_INTERNAL_SETUP_WEBAPI} = 1;
}

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::MockModule;
use Test::Mojo;
use Mojo::File qw(tempdir);
use Mojo::Transaction;
use Mojo::URL;
use MirrorCache::Auth::OAuth2;
use MirrorCache::Config;
use MirrorCache::Schema;
use MirrorCache::Schema::ResultSet::Acc;

# Mock database connections and migrations for unit tests
my $schema_mock = Test::MockModule->new('MirrorCache::Schema');
my $mock_singleton = bless {}, 'MockSchemaSingleton';
$schema_mock->redefine(connect_db => sub { $mock_singleton });
$schema_mock->redefine(singleton => sub { $mock_singleton });
no warnings 'once';
*MockSchemaSingleton::provider = sub { 'Pg' };
*MockSchemaSingleton::dsn = sub { 'dbi:Pg:' };
*MockSchemaSingleton::migrate = sub { 1 };
*MockSchemaSingleton::resultset = sub { bless {}, 'MockRS' };
*MockSchemaSingleton::storage = sub {
    bless {dbh => bless({}, 'MockDBH'),}, 'MockStorage';
};
*MockStorage::disconnect = sub { 1 };

my $tempdir = tempdir("mc-auth-XXXX", TMPDIR => 1);
my $ini_file = $tempdir->child("conf.ini");

sub test_auth_method_startup ($auth, @options) {
    my @conf = ("[default]\nroot = http://localhost\n", "[auth]\nmethod = $auth\n");
    $ini_file->spew(join("", @conf, @options));
    local $ENV{MIRRORCACHE_INI} = $ini_file->to_string;
    local $ENV{MIRRORCACHE_ROOT} = "http://localhost";
    local $ENV{MIRRORCACHE_INTERNAL_SETUP_WEBAPI} = 1;
    my $t = Test::Mojo->new("MirrorCache::WebAPI");
    $t->app->helper(schema => sub { $mock_singleton });
    is $t->app->auth_method, $auth, "started successfully with auth $auth";
    $t->get_ok("/login" => {Referer => "http://localhost/test/42"});
    return $t;
}

subtest OAuth2 => sub {
    my $ua_mock = Test::MockModule->new('Mojo::UserAgent');
    my $msg_mock = Test::MockModule->new('Mojo::Message');
    my $get_tx = Mojo::Transaction->new;
    my @get_args;
    $ua_mock->redefine(get => sub ($ua, @args) { push @get_args, [@args]; $get_tx });

    local $ENV{MIRRORCACHE_ROOT} = 'http://localhost';
    local $ENV{MIRRORCACHE_INTERNAL_SETUP_WEBAPI} = 1;
    my $t = Test::Mojo->new('MirrorCache::WebAPI');
    lives_ok { $t->app->plugin(OAuth2 => {mocked => {key => 'deadbeef'}}) } 'auth mocked';

    subtest 'auth_login function via /login route' => sub {
        throws_ok { test_auth_method_startup 'OAuth2' } qr/No OAuth2 provider selected/,
          'Error with no provider selected';
        throws_ok { test_auth_method_startup('OAuth2', ("[oauth2]\n", "provider = foo\n")) }
        qr/OAuth2 provider 'foo' not supported/, 'Error with unsupported provider';

        my $t_gh
          = test_auth_method_startup('OAuth2', ("[oauth2]\n", "provider = github\n", "key = k\n", "secret = s\n"));
        is $t_gh->tx->res->code, 302, 'got 302 redirect';
        like $t_gh->tx->res->headers->header('Location'), qr/github\.com/, 'redirection to GitHub';
        $t_gh->get_ok('/login?code=foo')->status_is(403, 'login with wrong code prevented');
    };

    my %main_cfg = (provider => 'custom');
    my %provider_cfg
      = (user_url => 'http://does-not-exist', token_label => 'bar', id_from => 'id', nickname_from => 'login');
    my %data = (access_token => 'some-token');
    my %expected_user = (username => 42, provider => 'oauth2@custom', nickname => 'Demo');

    my %db_users;
    my $mock_rs = bless {}, "MockRS";
    $t->app->helper(schema => sub { bless {}, "MockSchema" });
    no warnings 'once';
    *MockSchema::resultset = sub { $mock_rs };
    *MockRS::create_user = sub ($self, $id, %attrs) {
        my $u = bless {username => $id, %attrs}, "MockUser";
        $db_users{$id} = $u;
        return $u;
    };
    *MockUser::username = sub ($self) { $self->{username} };
    *MockUser::provider = sub ($self) { $self->{provider} };
    *MockUser::nickname = sub ($self) { $self->{nickname} };

    subtest 'failure when requesting user details' => sub {
        my $c = $t->app->build_controller;
        $get_tx->res->error({code => 500, message => 'Internal server error'});
        $msg_mock->unmock('json') if $msg_mock->is_mocked('json');
        MirrorCache::Auth::OAuth2::update_user($c, \%main_cfg, \%provider_cfg, \%data);
        is $c->res->code, 403, 'status code';
        is $c->res->body, '500 response: Internal server error', 'error message';
        is $c->session->{user}, undef, 'user not set';
        is_deeply \@get_args, [['http://does-not-exist', {Authorization => 'bar some-token'}]], 'args for get request';
    };

    subtest 'OAuth provider does not provide all mandatory user details' => sub {
        my $c = $t->app->build_controller;
        $get_tx->res->error(undef)->body('{}');
        $msg_mock->unmock('json') if $msg_mock->is_mocked('json');
        MirrorCache::Auth::OAuth2::update_user($c, \%main_cfg, \%provider_cfg, \%data);
        is $c->res->code, 403, 'status code';
        is $c->res->body, 'User data returned by OAuth2 provider is insufficient', 'error message';
        is $c->session->{user}, undef, 'user not set';
    };

    subtest 'requesting user details succeeds' => sub {
        my $c = $t->app->build_controller;
        $get_tx->res->error(undef);
        $msg_mock->redefine(json => sub { {id => 42, login => 'Demo'} });
        $t->app->helper(return_page => sub ($c) { 'http://test/foo/bar' });
        $t->app->config->{oauth2} = {provider_config => \%provider_cfg};
        throws_ok { MirrorCache::Auth::OAuth2::auth_login($c) } qr/invalid provider/i,
          'auth login executed as far as needed to assign return page';
        is $c->session->{return_page}, 'http://test/foo/bar', 'page to return to saved via session';
        MirrorCache::Auth::OAuth2::update_user($c, \%main_cfg, \%provider_cfg, \%data);
        is $c->res->code, 302, 'status code (redirection)';
        is $c->res->headers->header('Location'), '/foo/bar', 'redirection to previous page (only path/query)';
        is $c->session->{user}, '42', 'user set';
        is $db_users{42}->{provider}, 'oauth2@custom', 'user created with correct provider';
        is $db_users{42}->{nickname}, 'Demo', 'user created with correct nickname';
        MirrorCache::Auth::OAuth2::auth_logout($c);
        ok !exists $c->session->{return_page}, 'return page cleared on logout';
    };
};

subtest 'ResultSet::Acc provider support and collision prevention' => sub {
    my $rs_mock = Test::MockModule->new('MirrorCache::Schema::ResultSet::Acc');
    my %storage;

    my $rs = bless {}, 'MirrorCache::Schema::ResultSet::Acc';
    $rs_mock->redefine(
        find => sub ($self, $crit, @rest) {
            return $storage{$crit->{username}} if $crit->{username};
            return undef;
        });
    $rs_mock->redefine(
        update_or_new => sub ($self, $attrs) {
            return bless {in_storage => 0, %$attrs}, 'MockResultAcc';
        });
    no warnings 'once';
    *MockResultAcc::in_storage = sub ($s) { $s->{in_storage} };
    *MockResultAcc::provider = sub ($s) { $s->{provider} };
    *MockResultAcc::username = sub ($s) { $s->{username} };
    *MockResultAcc::email = sub ($s) { $s->{email} };
    *MockResultAcc::is_admin = sub ($s, @val) { @val ? $s->{is_admin} = $val[0] : $s->{is_admin} };
    *MockResultAcc::is_operator = sub ($s, @val) { @val ? $s->{is_operator} = $val[0] : $s->{is_operator} };
    *MockResultAcc::insert = sub ($s) {
        $s->{in_storage} = 1;
        $storage{$s->{username}} = $s;
        return $s;
    };

    my $user = $rs->create_user(100, provider => 'oauth2@github', nickname => 'testuser', email => 'user@suse.com');
    is $user->username, 100, 'username created';
    is $user->provider, 'oauth2@github', 'provider stored';
    is $user->is_admin, 1, 'first suse.com user becomes admin';

    my $same_user = $rs->create_user(100, provider => 'oauth2@github');
    is $same_user->username, 100, 'retrieved existing user with same provider';

    throws_ok { $rs->create_user(100, provider => 'openid') }
    qr/Auth provider mismatch: Account '100' is registered via 'oauth2\@github', but login attempted via 'openid'/,
      'prevent login when auth provider does not match existing account';
};

subtest 'OAuth2 Config initialization via INI and ENV' => sub {
    my $test_ini = $tempdir->child("oauth_test.ini");
    $test_ini->spew(<<"EOF");
[default]
root = http://localhost

[auth]
method = OAuth2

[oauth2]
provider = debian_salsa
key = salsakey
secret = salsasecret
EOF

    my $cfg = MirrorCache::Config->new;
    $cfg->init($test_ini->to_string);
    is $cfg->auth_method, 'OAuth2', 'auth_method read from INI';
    is $cfg->oauth2->{provider}, 'debian_salsa', 'provider read from INI';
    is $cfg->oauth2->{key}, 'salsakey', 'key read from INI';
    is $cfg->oauth2->{secret}, 'salsasecret', 'secret read from INI';

    # Override via environment variables
    local $ENV{MIRRORCACHE_OAUTH2_PROVIDER} = 'custom';
    local $ENV{MIRRORCACHE_OAUTH2_USER_URL} = 'https://custom.org/user';
    my $cfg_env = MirrorCache::Config->new;
    $cfg_env->init($test_ini->to_string);
    is $cfg_env->oauth2->{provider}, 'custom', 'ENV overrides INI provider';
    is $cfg_env->oauth2->{user_url}, 'https://custom.org/user', 'ENV sets user_url';
};

subtest 'SUSE ID custom OAuth2 provider' => sub {
    my $suse_ini = $tempdir->child("suse_oauth.ini");
    $suse_ini->spew(<<"EOF");
[default]
root = http://localhost

[auth]
method = OAuth2

[oauth2]
provider = custom
authorize_url = https://id.suse.com/application/o/authorize/?response_type=code
token_url = https://id.suse.com/application/o/token/
user_url = https://id.suse.com/application/o/userinfo/
token_scope = email profile openid sub communityUidAsopenId
token_label = Bearer
id_from = communityUidAsopenId
nickname_from = sub
unique_name = suseid
key = mysercretkey
secret = mysecretsecret
EOF

    local $ENV{MIRRORCACHE_INI} = $suse_ini->to_string;
    local $ENV{MIRRORCACHE_ROOT} = 'http://localhost';
    local $ENV{MIRRORCACHE_INTERNAL_SETUP_WEBAPI} = 1;

    my %db_users;
    my $mock_rs = bless {}, 'MockRS';
    my $t = Test::Mojo->new('MirrorCache::WebAPI');
    $t->app->helper(schema => sub { bless {}, 'MockSchema' });
    no warnings 'once';
    *MockSchema::resultset = sub { $mock_rs };
    *MockRS::create_user = sub ($self, $id, %attrs) {
        my $u = bless {username => $id, %attrs}, 'MockUser';
        $db_users{$id} = $u;
        return $u;
    };
    *MockUser::username = sub ($self) { $self->{username} };
    *MockUser::provider = sub ($self) { $self->{provider} };
    *MockUser::nickname = sub ($self) { $self->{nickname} };

    my $oauth2_cfg = $t->app->config->{oauth2};
    is $oauth2_cfg->{provider}, 'custom', 'custom provider selected';
    is $oauth2_cfg->{provider_config}->{unique_name}, 'suseid', 'unique_name is suseid';
    is $oauth2_cfg->{provider_config}->{id_from}, 'communityUidAsopenId', 'id_from is communityUidAsopenId';
    is $oauth2_cfg->{provider_config}->{nickname_from}, 'sub', 'nickname_from is sub';

    $t->get_ok('/login')->status_is(302, 'got 302 redirect for login');
    my $location = $t->tx->res->headers->header('Location');
    like $location, qr{https://id\.suse\.com/application/o/authorize/}, 'redirects to SUSE ID authorize URL';
    like $location, qr{client_id=mysercretkey}, 'includes SUSE ID client_id';
    like $location, qr{communityUidAsopenId}, 'includes communityUidAsopenId in scope';

    my $c = $t->app->build_controller;
    my $ua_mock = Test::MockModule->new('Mojo::UserAgent');
    my $msg_mock = Test::MockModule->new('Mojo::Message');
    my $get_tx = Mojo::Transaction->new;
    $ua_mock->redefine(get => sub ($ua, @args) { $get_tx });
    $msg_mock->redefine(
        json => sub {
            {
                communityUidAsopenId => 'suse-user-123',
                sub => 'alice',
                name => 'Alice Developer',
                email => 'alice@suse.com'
            }
        });

    MirrorCache::Auth::OAuth2::update_user(
        $c, $oauth2_cfg,
        $oauth2_cfg->{provider_config},
        {access_token => 'suse-token'});
    is $c->res->code, 302, 'status code 302 redirect';
    is $c->session->{user}, 'suse-user-123', 'session user set from communityUidAsopenId';
    is $db_users{'suse-user-123'}->{provider}, 'oauth2@suseid', 'user created with oauth2@suseid';
    is $db_users{'suse-user-123'}->{nickname}, 'alice', 'nickname set from sub';
    is $db_users{'suse-user-123'}->{fullname}, 'Alice Developer', 'fullname set from name';
    is $db_users{'suse-user-123'}->{email}, 'alice@suse.com', 'email set from email';
};

subtest 'openSUSE ID custom OAuth2 provider' => sub {
    my $opensuse_ini = $tempdir->child("opensuse_oauth.ini");
    $opensuse_ini->spew(<<"EOF");
[default]
root = http://localhost

[auth]
method = OAuth2

[oauth2]
provider = custom
authorize_url = https://id.opensuse.org/openidc/Authorization?response_type=code
token_url = https://id.opensuse.org/openidc/Token
user_url = https://id.opensuse.org/openidc/UserInfo
token_scope = openid profile email
token_label = Bearer
id_from = sub
nickname_from = nickname
unique_name = opensuse
key = myopensusekey
secret = mysecretsecret
EOF

    local $ENV{MIRRORCACHE_INI} = $opensuse_ini->to_string;
    local $ENV{MIRRORCACHE_ROOT} = 'http://localhost';
    local $ENV{MIRRORCACHE_INTERNAL_SETUP_WEBAPI} = 1;

    my %db_users;
    my $mock_rs = bless {}, 'MockRS';
    my $t = Test::Mojo->new('MirrorCache::WebAPI');
    $t->app->helper(schema => sub { bless {}, 'MockSchema' });
    no warnings 'once';
    *MockSchema::resultset = sub { $mock_rs };
    *MockRS::create_user = sub ($self, $id, %attrs) {
        my $u = bless {username => $id, %attrs}, 'MockUser';
        $db_users{$id} = $u;
        return $u;
    };
    *MockUser::username = sub ($self) { $self->{username} };
    *MockUser::provider = sub ($self) { $self->{provider} };
    *MockUser::nickname = sub ($self) { $self->{nickname} };

    my $oauth2_cfg = $t->app->config->{oauth2};
    is $oauth2_cfg->{provider}, 'custom', 'custom provider selected';
    is $oauth2_cfg->{provider_config}->{unique_name}, 'opensuse', 'unique_name is opensuse';
    is $oauth2_cfg->{provider_config}->{id_from}, 'sub', 'id_from is sub';
    is $oauth2_cfg->{provider_config}->{nickname_from}, 'nickname', 'nickname_from is nickname';

    $t->get_ok('/login')->status_is(302, 'got 302 redirect for login');
    my $location = $t->tx->res->headers->header('Location');
    like $location, qr{https://id\.opensuse\.org/openidc/Authorization}, 'redirects to openSUSE ID authorize URL';
    like $location, qr{client_id=myopensusekey}, 'includes openSUSE ID client_id';
    like $location, qr{openid}, 'includes openid in scope';

    my $c = $t->app->build_controller;
    my $ua_mock = Test::MockModule->new('Mojo::UserAgent');
    my $msg_mock = Test::MockModule->new('Mojo::Message');
    my $get_tx = Mojo::Transaction->new;
    $ua_mock->redefine(get => sub ($ua, @args) { $get_tx });
    $msg_mock->redefine(
        json => sub {
            {
                sub => 'https://id.opensuse.org/user/tux',
                nickname => 'tux',
                name => 'Tux Penguin',
                email => 'tux@opensuse.org'
            }
        });

    MirrorCache::Auth::OAuth2::update_user(
        $c, $oauth2_cfg,
        $oauth2_cfg->{provider_config},
        {access_token => 'opensuse-token'});
    is $c->res->code, 302, 'status code 302 redirect';
    is $c->session->{user}, 'https://id.opensuse.org/user/tux', 'session user set from sub';
    is $db_users{'https://id.opensuse.org/user/tux'}->{provider}, 'oauth2@opensuse', 'user created with oauth2@opensuse';
    is $db_users{'https://id.opensuse.org/user/tux'}->{nickname}, 'tux', 'nickname set from nickname';
    is $db_users{'https://id.opensuse.org/user/tux'}->{fullname}, 'Tux Penguin', 'fullname set from name';
    is $db_users{'https://id.opensuse.org/user/tux'}->{email}, 'tux@opensuse.org', 'email set from email';
};

done_testing;
