package Directory::Scanner::OBSReleaseInfo;

use Mojo::Base -base, -signatures;

has ['type', 'version', 'versionfilename', 'versionmtime'];

sub new($class, $type, $mtime) {
    my $self = Mojo::Base::new($class);
    $mtime = 0 unless $mtime;
    $self->type($type);
    $self->versionmtime($mtime);
    $self->versionfilename('');
}

sub next_file($self, $filename, $mtime) {
    return 0 unless $mtime;
    return 0 if $self->versionmtime > $mtime;
    if ($self->type eq 'iso') {
        if ($filename =~ /.*(Build|Snapshot)((\d)+\.?(\d*))-Media\.iso$/) {
            $self->version($2);
            $self->versionfilename($filename);
            $self->versionmtime($mtime);
            return 1;
        }
    } elsif ($self->type eq 'repo') {
        if ($filename =~ /.*primary.xml(.(gz|zst))$/) {
            my $version = $mtime;
            $self->version($version);
            $self->versionfilename($filename);
            $self->versionmtime($mtime);
            return 1;
        }
    }
    return 0;
}

1;
