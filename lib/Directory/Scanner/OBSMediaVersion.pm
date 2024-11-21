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


# return name, version, build, arch, ext
sub parse_pkg($filename) {
    return undef unless $filename;
    my $fil = Mojo::File->new($filename);
    my $f = $fil->basename;
    my $ext = $fil->extname;
    if ($ext eq "rpm") {
        my @res = parse_pkg_rpm( $fil->basename($ext) );
        return ( @res, "rpm" );
    } elsif ($ext eq "deb") {
        my @res = parse_pkg_deb( $fil->basename($ext) );
        return ( @res, "deb" );
    }
    return undef;
}

# return name, version, build, arch
sub parse_pkg_rpm($basename) {
    return undef unless ($basename =~ m/(.*)-([^-]+)-([^-]+)\.(x86_64|noarch|i[3-6]86|ppc64|aarch64|arm64|amd64|s390|src)/);
    return ($1, $2, $3, $4);
}

sub parse_pkg_deb($basename) {
    return undef;
}

1;
