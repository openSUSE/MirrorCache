use Mojo::Base -strict;

use Test::More;
use POSIX;
use MirrorCache::WebAPI::Plugin::Dir;

# Define methods for Mock classes
sub MockController::schema { shift->{schema} }
sub MockController::mc { shift->{mc} }
sub MockController::res { shift->{res} }
sub MockController::render {
    my $self = shift;
    if (scalar(@_) % 2 == 1) {
        my $template = shift;
        $self->{rendered_template} = $template;
    }
    $self->{rendered} = { @_ };
}
sub MockController::mcbranding { 'suse' }

sub MockSchema::resultset {
    my ($self, $type) = @_;
    return bless {}, 'MockRS';
}

sub MockRS::find_with_regex {
    return {
        1 => {
            name  => 'file1.txt',
            size  => 1024,
            mtime => 1661211960, # 22-Aug-2022 23:46:00
        },
        2 => {
            name  => 'file2.txt',
            size  => 2048,
            mtime => 1661212020, # 22-Aug-2022 23:47:00
        }
    };
}

sub MockResponse::headers { shift->{headers} }

sub MockHeaders::etag {
    my ($self, $etag) = @_;
    $self->{etag} = $etag if defined $etag;
    return $self->{etag};
}
sub MockHeaders::add {
    my ($self, $key, $val) = @_;
    $self->{$key} = $val;
}

# Mock the Controller
my $c = bless {
    mc => bless({
        root => bless({
            rooturl => 'http://example.com'
        }, 'MockRoot')
    }, 'MockMC'),
    schema => bless({}, 'MockSchema'),
    res => bless({
        headers => bless({}, 'MockHeaders')
    }, 'MockResponse'),
    rendered => undef,
}, 'MockController';

# Also need MockRoot methods
sub MockRoot::rooturl { shift->{rooturl} }

# Mock the Datamodule
my $dm = bless {
    c => $c,
    json => 0,
    browse => 0,
    glob_regex => undef,
    regex => undef,
    folder_sync_last => undef,
    folder_sync_requested => undef,
    route => 'download',
    mime => 'text/plain',
    jsontable => 0,
}, 'MockDM';

sub MockDM::c { shift->{c} }
sub MockDM::json { shift->{json} }
sub MockDM::browse { shift->{browse} }
sub MockDM::glob_regex { shift->{glob_regex} }
sub MockDM::regex { shift->{regex} }
sub MockDM::folder_sync_last { shift->{folder_sync_last} }
sub MockDM::folder_sync_requested { shift->{folder_sync_requested} }
sub MockDM::route { shift->{route} }
sub MockDM::mime { shift->{mime} }
sub MockDM::jsontable { shift->{jsontable} }

subtest 'render_dir_from_db max_mtime and warning-free comparison' => sub {
    my @warnings;
    {
        local $SIG{__WARN__} = sub { push @warnings, shift };
        MirrorCache::WebAPI::Plugin::Dir::_render_dir_from_db($dm, 1, '/some/dir');
    }

    is_deeply \@warnings, [], "No warnings generated during rendering";

    # Let's verify that the calculated ETag is based on the maximum numeric mtime (1661212020 = 0x630416F4)
    # The ETag format is: sprintf('%X', scalar(@files)) . '-' . sprintf('%X', $max_mtime)
    # 2 files, so: 2-630416F4
    my $expected_etag = sprintf('%X', 2) . '-' . sprintf('%X', 1661212020);
    is $c->res->headers->etag, $expected_etag, "ETag matches expected value based on numeric mtime";
};

done_testing();
