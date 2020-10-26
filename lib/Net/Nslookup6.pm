package Net::Nslookup6;

# -------------------------------------------------------------------
# Net::Nslookup6 - fork of Net::Nslookup with IPv6 support
# Read upstream for license and documentation.
# Added one line to support AAAA record type
# -------------------------------------------------------------------

use strict;
use vars qw($VERSION $DEBUG @EXPORT $TIMEOUT $WIN32);
use base qw(Exporter);

$VERSION    = "2.04";
@EXPORT     = qw(nslookup);
$DEBUG      = 0 unless defined $DEBUG;
$TIMEOUT    = 15 unless defined $TIMEOUT;
$WIN32      = $^O =~ /win32/i; 

use Exporter;

my %_methods = qw(
    A       address
    AAAA    address
    CNAME   cname
    MX      exchange
    NS      nsdname
    PTR     ptrdname
    TXT     rdatastr
    SOA     dummy
    SRV     target
);

# ----------------------------------------------------------------------
# nslookup(%args)
#
# Does the actual lookup, deferring to helper functions as necessary.
# ----------------------------------------------------------------------
sub nslookup {
    my $options = isa($_[0], 'HASH') ? shift : @_ % 2 ? { 'host', @_ } : { @_ };
    my ($term, $type, @answers);

    # Some reasonable defaults.
    $term = lc ($options->{'term'} ||
                $options->{'host'} ||
                $options->{'domain'} || return);
    $type = uc ($options->{'type'} ||
                $options->{'qtype'} || "A");
    $options->{'server'} ||= '';
    $options->{'recurse'} ||= 0;

    $options->{'timeout'} = $TIMEOUT
        unless defined $options->{'timeout'};

    $options->{'debug'} = $DEBUG 
        unless defined $options->{'debug'};

    eval {
        local $SIG{ALRM} = sub { die "alarm\n" };
        alarm $options->{'timeout'} unless $WIN32;

        my $meth = $_methods{ $type } || die "Unknown type '$type'";
        my $res = ns($options->{'server'});

        if ($options->{'debug'}) {
            warn "Performing `$type' lookup on `$term'\n";
        }

        if (my $q = $res->search($term, $type)) {
            if ('SOA' eq $type) {
                my $a = ($q->answer)[0];
                @answers = (join " ", map { $a->$_ }
                    qw(mname rname serial refresh retry expire minimum));
            }
            else {
                @answers = map { $_->$meth() } grep { $_->type eq $type } $q->answer;
            }

            # If recurse option is set, for NS, MX, and CNAME requests,
            # do an A lookup on the result.  False by default.
            if ($options->{'recurse'}   &&
                (('NS' eq $type)        ||
                 ('MX' eq $type)        ||
                 ('CNAME' eq $type)
                )) {

                @answers = map {
                    nslookup(
                        host    => $_,
                        type    => "A",
                        server  => $options->{'server'},
                        debug   => $options->{'debug'}
                    );
                } @answers;
            }
        }

        alarm 0 unless $WIN32;
    };

    if ($@) {
        die "nslookup error: $@"
            unless $@ eq "alarm\n";
        warn qq{Timeout: nslookup("type" => "$type", "host" => "$term")};
    }

    return $answers[0] if (@answers == 1);
    return (wantarray) ? @answers : $answers[0];
}

{
    my %res;
    sub ns {
        my $server = shift || "";

        unless (defined $res{$server}) {
            require Net::DNS;
            import Net::DNS;
            $res{$server} = Net::DNS::Resolver->new;

            # $server might be empty
            if ($server) {
                if (ref($server) eq 'ARRAY') {
                    $res{$server}->nameservers(@$server);
                }
                else {
                    $res{$server}->nameservers($server);
                }
            }
        }

        return $res{$server};
    }
}

sub isa { &UNIVERSAL::isa }

1;
__END__

=head1 NAME

Net::Nslookup6 - fork of Net::Nslookup with IPv6 support
Read upstream for license and documentation.
Added support of AAAA record type

=head1 SYNOPSIS

  use Net::Nslookup6;

  my $a = nslookup(type => "AAAA", domain => "perl.org");
