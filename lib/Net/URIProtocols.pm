package Net::URIProtocols;

use strict;
use vars qw($VERSION $DEBUG @EXPORT $TIMEOUT $WIN32);
use base qw(Exporter);

$VERSION    = "0.01";
# TODO ProbeFtp ProbeFtps
@EXPORT     = qw(ProbeHttp ProbeHttps ProbeIpv4 ProbeIpv6 ProbeAll);
$DEBUG      = 0 unless defined $DEBUG;
$TIMEOUT    = 15 unless defined $TIMEOUT;

use Exporter;
use Net::Nslookup6;
use Mojo::UserAgent;

my @_protocols = qw(
    http
    https
    ipv4
    ipv6
);


# 0 means success, otherwise it returns something error related
sub ProbeHttp {
    my ($uri, $ua) = @_;
    $ua = $ua || Mojo::UserAgent->new()->max_redirects(5)->connect_timeout(3)->request_timeout(3);

    my $url = "http://$uri";
    return _probe_url($url, $ua);
}

sub ProbeHttps {
    my ($uri, $ua) = @_;
    $ua = $ua || Mojo::UserAgent->new()->max_redirects(5)->connect_timeout(3)->request_timeout(3);

    my $url = "https://$uri";
    return _probe_url($url, $ua);
}

sub ProbeIpv4 {
    my ($uri) = @_;
    my $domain = _parse_uri($uri);
    return 0 if $domain eq '127.0.0.1' || $domain eq '::ffff:127.0.0.1'; # rather workaround for now
    return 1 if $domain eq '::1'; # rather workaround for now
    my $a = nslookup(type => "A", domain => $domain);
    return 0 if $a;
    return 1;
}

sub ProbeIpv6 {
    my ($uri) = @_;
    my $domain = _parse_uri($uri);
    return 0 if $domain eq '::1' || $domain eq '::ffff:127.0.0.1'; # rather workaround for now
    return 1 if $domain eq '127.0.0.1'; # rather workaround for now
    my $a = nslookup(type => "AAAA", domain => $domain);
    return 0 if $a;
    return 1;
}

# returns hash with error info after checking correcponding protocols
# 0 means no error
sub ProbeAll {
    my ($uri, $ua) = @_;
    $ua = $ua || Mojo::UserAgent->new()->max_redirects(5)->connect_timeout(3)->request_timeout(3);

    my %ret;
    $ret{'http'}  = ProbeHttp($uri, $ua);
    $ret{'https'} = ProbeHttps($uri, $ua);
    # $ret{'ftp'} = ProbeFtp($uri);
    # $ret{'ftps'}= ProbeFtps($uri);
    $ret{'ipv4'}  = ProbeIpv4($uri);
    $ret{'ipv6'}  = ProbeIpv6($uri);
    return \%ret;
}

sub _probe_url {
    my ($url, $ua) = @_;

    my $code = 0;
    eval {
        $code = $ua->head($url)->result->code;
        1;
    } or return $@;

    return 0 if ($code > 199 && $code < 300);
    return $code;
}

sub _parse_uri {
    my $uri = shift;
    my $domain;
    if ($uri =~ /^(\[?(\d+)?(::\d+)+\]?|[^:\/]+)/) {
        $domain = $3 || $1;
        return $domain;
    }
    return $uri;
}

1;

=head1 NAME

Net::URIProtocols - check if a hostname supports ipv6 ipv4 http and https

=head1 SYNOPSIS

    > # returns hash with errors after checking corresponding protocol
    > perl -MNet::URIProtocols -MData::Dumper -e 'print Dumper(ProbeAll("example.com"))' 
        $VAR1 = {
          'ipv4' => 0,
          'http' => 0,
          'https' => 0,
          'ipv6' => 0
        };

=head1 SEE ALSO

L<Net::Nslookup> L<Mojo::UserAgent>.

=cut
