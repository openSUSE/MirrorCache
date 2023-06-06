package Digest::Metalink;

use Mojo::Base -base, -signatures;

use POSIX;

sub build_metalink($dirname, $basename, $mirrors, $options) {
    my $writer = XML::Writer->new(OUTPUT => 'self', DATA_MODE => 1, DATA_INDENT => 2, );
    $writer->xmlDecl('UTF-8');
    my @attribs = (
        version => '3.0',
        xmlns => 'http://www.metalinker.org/',
        type => 'dynamic',
    );
    if (my $origin = $options->{origin}) {
        push @attribs, (origin => "$origin.metalink");
    }
    if (my $generator = $options->{generator}) {
        push @attribs, (generator => $generator);
    }
    push @attribs, (pubdate => strftime("%Y-%m-%d %H:%M:%S %Z", localtime time));

    $writer->startTag('metalink', @attribs);

    my $publisher = $options->{publisher};
    my $publisher_url = $options->{publisher_url};
    if ($publisher || $publisher_url) {
        $writer->startTag('publisher');
        $writer->dataElement( name => $publisher    ) if $publisher;
        $writer->dataElement( url  => $publisher_url) if $publisher_url;
        $writer->endTag('publisher');
    }

    $writer->startTag('files');
    {
        $writer->startTag('file', name => $basename);
        if (my $file_size = $options->{file_size}) {
            $writer->dataElement( size => $file_size );
        }
        if (my $file_mtime = $options->{file_mtime}) {
            $writer->comment('<mtime>' . $file_mtime . '</mtime>');
        }
        $writer->startTag('resources');
        my $preference = 100;
        for my $m (@$mirrors) {
            my $url;
            my @attrs;
            if (ref $m eq 'HASH') {
                $url = $m->{url};
                push (@attrs, location => $m->{location}) if ($m->{location});
            } else {
                $url = $m;
            }
            next unless $url;
            if ((my $colon = index(substr($url,0,6), ':')) > 0) {
                my $type = lc(substr($url,0,$colon));
                push @attrs, type => $type;
            }
            push @attrs, preference => $preference--;
            $writer->startTag('url', @attrs);
            $writer->characters($url . $dirname . '/' . $basename);
            $writer->endTag('url');
        }
        $writer->endTag('resources');
        $writer->endTag('file');
    }
    $writer->endTag('files');
    $writer->endTag('metalink');

    return $writer->end();
}


1;
