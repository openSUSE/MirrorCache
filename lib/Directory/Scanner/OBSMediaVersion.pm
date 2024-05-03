package Directory::Scanner::OBSMediaVersion;

use Mojo::Base -base, -signatures;
use Mojo::File;

sub parse_version($filename) {
    return undef unless $filename;
    my $f = Mojo::File->new($filename);
    $f = $f->basename;

    if ($filename =~ /.*(Build|Snapshot)((\d)+(\.\d+)?).*/) {
        return $2
    }

    if ($filename =~ /.*-(\d+\.?\d*\.?\d*\.?\d*)-(\d*\.?\d*)?.*(\.d?rpm)?$/) {
        return $1;
    }

    return undef unless $filename =~ /.*_(\d+\.?\d*\.?\d*\.?\d*)-(\d*\.?\d*)?.*(\.deb)?$/;
    return $1
}

1;
