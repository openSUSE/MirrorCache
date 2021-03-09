# this helper script is used in testing File::Listing::Rsync;

use File::Listing::Rsync;

my ($url, $dir) = @ARGV;

my $r = File::Listing::Rsync->new->init($url);
my $callback = sub {
    my ($name, $size, $mod, $dt) = @_;
    print "name = $name; size = $size; mod = $mod; dt = $dt\n";
};

$r->readdir($dir, $callback);
