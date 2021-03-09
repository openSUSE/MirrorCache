# this helper script is used in testing File::Listing::Rsync;
use File::Listing::Rsync;

my ($host, $port, $user, $pass, $module, $path) = @ARGV;

my $r = File::Listing::Rsync->new;
$r->set_host($host);
$r->port($port)     if $port;
$r->module($module) if $module;
$r->user($user)     if $user;
$r->pass($pass)     if $pass;

require Digest::MD4;
$r->have_md4(1);

my $callback = sub {
    my ($name, $size, $mod, $dt) = @_;
    print "name = $name; size = $size; mod = $mod; dt = $dt\n";
};

$r->callback($callback);

$r->readdir($path);
