# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -signatures;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::MockModule;

use MirrorCache::Schema::ResultSet::Folder;
use MirrorCache::Task::FolderSync;

subtest 'ResultSet::Folder::delete_redirect sql execution' => sub {
    my $rs = bless {}, 'MirrorCache::Schema::ResultSet::Folder';
    my @executed_sql;
    my @executed_bind;

    my $mock_prep = bless {}, 'MockPrep';
    no warnings 'once';
    *MockPrep::execute = sub ($self, @args) {
        push @executed_bind, [@args];
        return 1;
    };

    my $mock_dbh = bless {}, 'MockDBH';
    *MockDBH::prepare = sub ($self, $sql) {
        push @executed_sql, $sql;
        return $mock_prep;
    };

    my $mock_storage = bless { dbh => $mock_dbh }, 'MockStorage';
    *MockStorage::dbh = sub ($self) { $self->{dbh} };

    my $mock_schema = bless { storage => $mock_storage }, 'MockSchema';
    *MockSchema::storage = sub ($self) { $self->{storage} };

    my $mock_rsource = bless { schema => $mock_schema }, 'MockRSource';
    *MockRSource::schema = sub ($self) { $self->{schema} };

    my $rs_mock = Test::MockModule->new('MirrorCache::Schema::ResultSet::Folder');
    $rs_mock->redefine(result_source => sub { $mock_rsource });

    # Call delete_redirect
    my $res = $rs->delete_redirect('/ports/armv7hl/tumbleweed/appliances');
    is scalar(@executed_sql), 1, 'prepared one SQL statement';
    like $executed_sql[0], qr/DELETE FROM redirect WHERE pathfrom = \?/, 'correct DELETE SQL query';
    is_deeply $executed_bind[0], ['/ports/armv7hl/tumbleweed/appliances'], 'bind parameter is correct pathfrom';

    # Calling with undef does nothing
    @executed_sql = ();
    $rs->delete_redirect(undef);
    is scalar(@executed_sql), 0, 'empty path does not execute SQL';
};

subtest 'FolderSync::_sync cleans up stale redirect when symlink is removed' => sub {
    my $sync_task = MirrorCache::Task::FolderSync->new;

    # Mock minion and job
    my %job_notes;
    my $finished_msg;
    my $job = bless {}, 'MockJob';
    no warnings 'once';
    *MockJob::note = sub ($s, %args) { %job_notes = (%job_notes, %args); };
    *MockJob::finish = sub ($s, $msg = '') { $finished_msg = $msg; return 'FINISHED'; };
    *MockJob::fail = sub ($s, $msg = '') { die "Job failed: $msg"; };

    my $minion = bless {}, 'MockMinion';
    *MockMinion::guard = sub { 1 };

    # Mock root
    my $symlink_target = '/ports/aarch64/tumbleweed/appliances';
    my $root = bless {}, 'MockRoot';
    *MockRoot::realpath = sub ($s, $path, $deep = 0) {
        return $symlink_target if defined $symlink_target && $symlink_target ne $path;
        return $path;
    };
    *MockRoot::is_dir = sub { 1 };
    *MockRoot::foreach_filename = sub { 1 };

    # Mock schema & resultset
    my @deleted_redirects;
    my @added_redirects;

    my $folder_rs = bless {}, 'MockFolderRS';
    *MockFolderRS::add_redirect = sub ($s, $from, $to) { push @added_redirects, [$from, $to]; };
    *MockFolderRS::delete_redirect = sub ($s, $from) { push @deleted_redirects, $from; };
    *MockFolderRS::find = sub { undef };

    my $rollout_rs = bless {}, 'MockRolloutRS';
    *MockRolloutRS::project_for_folder = sub { undef };

    my $schema = bless {}, 'MockSchema2';
    *MockSchema2::resultset = sub ($s, $name) {
        return $folder_rs if $name eq 'Folder';
        return $rollout_rs if $name eq 'Rollout';
        return bless {}, 'MockGenericRS';
    };

    # Mock app
    my $app = bless {
        minion => $minion,
        schema => $schema,
        mc     => bless({ root => $root }, 'MockMC'),
        backstage => bless({}, 'MockBackstage'),
    }, 'MockApp';
    no warnings 'once';
    *MockMC::root    = sub ($s) { $s->{root} };
    *MockApp::minion = sub ($s) { $s->{minion} };
    *MockApp::schema = sub ($s) { $s->{schema} };
    *MockApp::mc     = sub ($s) { $s->{mc} };
    *MockApp::backstage = sub ($s) { $s->{backstage} };
    *MockBackstage::enqueue = sub { 1 };

    # 1. When symlink exists, it adds redirect
    MirrorCache::Task::FolderSync::_sync($app, $job, '/ports/armv7hl/tumbleweed/appliances', 0);
    is_deeply \@added_redirects, [['/ports/armv7hl/tumbleweed/appliances', '/ports/aarch64/tumbleweed/appliances']],
        'add_redirect called when realpath ne path';
    is $finished_msg, 'redirected to /ports/aarch64/tumbleweed/appliances', 'job finished with redirect';
    is scalar(@deleted_redirects), 0, 'no redirect deleted while symlink exists';

    # 2. When symlink is removed on disk, realpath equals path => delete_redirect must be called
    $symlink_target = undef; # symlink removed
    @added_redirects = ();
    @deleted_redirects = ();
    $finished_msg = undef;

    # Mock File search and other methods for normal folder sync
    my $file_rs = bless {}, 'MockFileRS';
    *MockFileRS::search = sub { () };
    *MockSchema2::resultset = sub ($s, $name) {
        return $folder_rs if $name eq 'Folder';
        return $rollout_rs if $name eq 'Rollout';
        return $file_rs if $name eq 'File';
        return bless {}, 'MockGenericRS';
    };

    my $mock_folder_row = bless { id => 123 }, 'MockFolderRow';
    *MockFolderRow::id = sub { 123 };
    *MockFolderRow::update = sub { 1 };
    *MockFolderRS::find = sub { $mock_folder_row };

    my $mock_dbh2 = bless {}, 'MockDBH2';
    *MockDBH2::do = sub { 1 };
    my $mock_storage2 = bless { dbh => $mock_dbh2 }, 'MockStorage2';
    *MockStorage2::dbh = sub { $mock_dbh2 };
    *MockSchema2::storage = sub { $mock_storage2 };

    MirrorCache::Task::FolderSync::_sync($app, $job, '/ports/armv7hl/tumbleweed/appliances', 0);
    is_deeply \@deleted_redirects, ['/ports/armv7hl/tumbleweed/appliances'],
        'delete_redirect called to clean up stale redirect when realpath eq path';

    # 3. When folder is removed completely and passes grace period, delete_redirect must be called
    @deleted_redirects = ();
    my $deleted_cascade_id;
    *MockRoot::is_dir = sub { 0 };
    *MockFolderRS::delete_cascade = sub ($s, $id, $only_diff) { $deleted_cascade_id = $id; };
    *MockJob::info = sub { { started => 100000 } };

    my $jobs_iterator = bless {
        items => [{ finished => 50000, result => '/ports/armv7hl/tumbleweed/appliances is not a dir anymore' }],
    }, 'MockJobsIterator';
    *MockJobsIterator::next = sub ($s) { shift @{$s->{items}} };
    *MockMinion::jobs = sub { $jobs_iterator };

    $ENV{MIRRORCACHE_FOLDER_DELETE_JOB_GRACE_TIMEOUT} = 100;

    MirrorCache::Task::FolderSync::_sync($app, $job, '/ports/armv7hl/tumbleweed/appliances', 0);
    is_deeply \@deleted_redirects, ['/ports/armv7hl/tumbleweed/appliances'],
        'delete_redirect called when folder is deleted from disk';
    is $deleted_cascade_id, 123, 'delete_cascade called for folder';
    is $finished_msg, 'folder has been successfully deleted from DB', 'job finished with deletion message';
};

done_testing;
