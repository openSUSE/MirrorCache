package Digest::Meta4;

use Mojo::Base -base, -signatures;

use POSIX;

sub build_meta4($dirname, $basename, $mirrors, $options) {
    my $writer = XML::Writer->new(OUTPUT => 'self', DATA_MODE => 1, DATA_INDENT => 2, );
    $writer->xmlDecl('UTF-8');
    $writer->startTag('metalink', xmlns => 'urn:ietf:params:xml:ns:metalink');
    if (my $generator = $options->{generator}) {
        $writer->dataElement(generator => $generator);
    }
    if (my $origin = $options->{origin}) {
        $writer->dataElement(origin => "$origin.metalink");
    }

    my $publisher = $options->{publisher};
    my $publisher_url = $options->{publisher_url};
    if ($publisher || $publisher_url) {
        $writer->startTag('publisher');
        $writer->dataElement( name => $publisher    ) if $publisher;
        $writer->dataElement( url  => $publisher_url) if $publisher_url;
        $writer->endTag('publisher');
    }
    {
        $writer->startTag('file', name => $basename);

        if (my $file_size = $options->{file_size}) {
            $writer->dataElement( size => $file_size );
        }
        if (my $file_mtime = $options->{file_mtime}) {
            $writer->comment('<mtime>' . $file_mtime . '</mtime>');
        }
        my $priority = 1;
        for my $m (@$mirrors) {
            my $url;
            my @attrs;
            if (ref $m eq 'HASH') {
                $url = $m->{url};
                push (@attrs, location => uc($m->{location})) if ($m->{location});
            } else {
                $url = $m;
            }
            next unless $url;
            push @attrs, priority => $priority++;
            $writer->startTag('url', @attrs);
            $writer->characters($url . $dirname . '/' . $basename);
            $writer->endTag('url');
        }
        $writer->endTag('file');
    }
    $writer->endTag('metalink');

    return $writer->end();
}


1;
