# the idea and big part taken from mirrorbrain/tools/scanner.pl
package File::Listing::Rsync;

use Mojo::Base -base;
use Socket;
# use Mojo::Exception;
use Data::Dumper;

has 'addr';
has port => 873;
has 'user';
has 'pass';
has 'module';
has 'basedir';
has 'protocol';
has 'have_md4';
has timeout => 600;

has callback => sub {
    ;
};

has __rsync_muxbuf => '';

sub set_host {
    my ($self, $host) = @_;

    eval {
        $self->addr(inet_aton($host));
        1;
    } or $self->addr($host);
}

#  rsync://user:passwd@ftp.sunet.se/pub/Linux/distributions/opensuse/#@^opensuse/@@
sub init {
    my ($self, $url, $callback) = @_;
    $self->callback($callback);

    $self->have_md4(0);
    eval {
        require Digest::MD4;
        $self->have_md4(1);
    };

    return $self unless $url;

    $url =~ s{^rsync://}{}s; # trailing s: treat as single line, strip off protocol id
    if ($url =~ s{^(.*?)@}{}) { # username/passwd if specified
        my $cred = $1;
        $self->pass($1) if $cred =~ s{:(.*)}{};
        $self->user($cred);
    }

    die "Cannot parse url '$url'\n" unless $url =~ m{^([^:/]+)(:(\d*))(/(.*))?$};
    my ($host, $_, $port, $path) = ($1,$2,$3,$4);
    $path = $5 if $path;
    $self->set_host($host);
    $self->port($port) if $port;
    my $module  = '', my $basedir = '';
    if ($path && ( my $i = index($path, '/', 1) > -1) ) {
        $module  = substr($path, 0, $i);
        $basedir = substr($path, $i);
    } else {
        $module = $path;
    }
    $self->module($module);
    $self->basedir($basedir);

    return $self;
}

sub readdir {
    my ($self, $path, $callback) = @_;
    $path = '' unless $path;
    $callback = $self->callback unless $callback;
    $self->__rsync_muxbuf('');
    # remove leading slash
    my $firstChar = substr($path,0,1);
    if ($firstChar eq '/') {
        $path = substr($path,1);
    }
    my $cnt = 0;

    my $tcpproto = getprotobyname('tcp');
    socket(S, PF_INET, SOCK_STREAM, $tcpproto) || die "socket: $!\n";
    setsockopt(S, SOL_SOCKET, SO_KEEPALIVE, pack("l",1));
    connect(S, sockaddr_in($self->port, $self->addr)) || die "connect $!\n";

    my $hello = "\@RSYNCD: 28\n";
    swrite(*S, $hello);
    my $buf = '';
    alarm $self->timeout;
    sysread(S, $buf, 4096);
    alarm 0;
    die("protocol error1 [Dumper($buf)]\n") if $buf !~ /^\@RSYNCD: ([\d.]+)\n/s;
    $self->protocol($1);
    my $module = $self->module;
    if ($module) {
        $path = $self->basedir . $path if $self->basedir;
    } else {
        if (my $i = index($path, '/', 0) > -1) {
            $module = substr($path, 0, $i);
            $path   = substr($path, $i+1);
        }
    }
    swrite(*S, "$module\n");
    while(1) {
        # alarm $self->timeout;
        alarm 800;
        sysread(S, $buf, 4096);
        alarm 0;
        die("protocol error2 [Dumper($buf)]\n") if $buf !~ s/\n//s;
        last if $buf eq "\@RSYNCD: OK";
        die("rsync error $buf\n") if $buf =~ /^\@ERROR/s;
        if($buf =~ /^\@RSYNCD: AUTHREQD /) {
            die("'$module' needs authentification, but Digest::MD4 is not installed\n") unless $self->have_md4;

            my ($user,$pass)=($self->user // 'nobody', $self->pass // '');
            my $digest = "$user ".Digest::MD4::md4_base64("\0\0\0\0$pass".substr($buf, 18))."\n";
            swrite(*S, $digest);
            next;
        }
    }
    my @args = ('--server', '--sender', '-rl');
    push @args, '--exclude=/*/*';

    for my $arg (@args, '.', "$path/.", '') {
        swrite(*S, "$arg\n");
    }
    sread(*S, 4);	# checksum seed
    swrite(*S, "\0\0\0\0");
    my $name = '';
    my $mtime = 0;
    my $mode = 0;
    my $uid = 0;
    my $gid = 0;
    my $flags;
    while(1) {
        $flags = $self->muxread(*S, 1);
        $flags = ord($flags);
        last if $flags == 0;
        $flags |= ord($self->muxread(*S, 1)) << 8 if $self->protocol >= 28 && ($flags & 0x04) != 0;
        my $l1 = $flags & 0x20 ? ord($self->muxread(*S, 1)) : 0;
        my $l2 = $flags & 0x40 ? unpack('V', $self->muxread(*S, 4)) : ord($self->muxread(*S, 1));
        $name = substr($name, 0, $l1).$self->muxread(*S, $l2);
        my $len = unpack('V', $self->muxread(*S, 4));
        if($len == 0xffffffff) {
            $len = unpack('V', $self->muxread(*S, 4));
            my $len2 = unpack('V', $self->muxread(*S, 4));
            $len += $len2 * 4294967296;
        }
        $mtime = unpack('V', $self->muxread(*S, 4)) unless $flags & 0x80;
        $mode = unpack('V', $self->muxread(*S, 4)) unless $flags & 0x02;
        my $mmode = $mode & 07777;
        if(($mode & 0170000) == 0100000) {
            $mmode |= 0x1000;
        } elsif (($mode & 0170000) == 0040000) {
            $mmode |= 0x0000;
        } elsif (($mode & 0170000) == 0120000) {
            $mmode |= 0x2000;
            $self->muxread(*S, unpack('V', $self->muxread(*S, 4)));
        } else {
            next;
        }
        # sort and process buffer when folder changes
        my $res = $callback->($name, $len, $mmode, $mtime) if $callback;
        last if $res && $res eq 2;
        $cnt++;
    }
    my $io_error = unpack('V', $self->muxread(*S, 4));

    # rsync_send_fin
    swrite(*S, pack('V', -1));      # switch to phase 2
    swrite(*S, pack('V', -1));      # switch to phase 3
    if($self->protocol >= 24) {
        swrite(*S, pack('V', -1));    # goodbye
    }
    close(S);
    return $cnt;
}

#######################################################################
# rsync protocol
#######################################################################
#
# Copyright (c) 2005 Michael Schroeder (mls@suse.de)
#
# This program is licensed under the BSD license, read LICENSE.BSD
# for further information
#
sub sread
{
  local *SS = shift;
  my $len = shift;
  my $ret = '';
  while($len > 0) {
    alarm 600;
    my $r = sysread(SS, $ret, $len, length($ret));
    alarm 0;
    die("read error") unless $r;
    $len -= $r;
    die("read too much") if $r < 0;
  }
  return $ret;
}

sub swrite
{
  local *SS = shift;
  my ($var, $len) = @_;
  $len = length($var) unless defined $len;
  return if $len == (syswrite(SS, $var, $len) || 0);
  warn "syswrite: $!\n";
}

sub muxread {
  my $self = shift;
  local *SS = shift;
  my $len = shift // 0;
  my $rsync_muxbuf = $self->__rsync_muxbuf;

  while(length($rsync_muxbuf) < $len) {
    my $tag = '';
    $tag = sread(*SS, 4);
    $tag = unpack('V', $tag);
    my $tlen = 0+$tag & 0xffffff;
    $tag >>= 24;
    if ($tag == 7) {
      $rsync_muxbuf .= sread(*SS, $tlen);
      next;
    }
    if ($tag == 8 || $tag == 9) {
      my $msg = sread(*SS, $tlen);
      warn("tag=8 $msg\n") if $tag == 8;
      # print "info: $msg\n";
      next;
    }
    # warn("$identifier: unknown tag: $tag\n");
    return undef;
  }
  my $ret = substr($rsync_muxbuf, 0, $len);
  $self->__rsync_muxbuf(substr($rsync_muxbuf, $len));
  return $ret;
}

1;
