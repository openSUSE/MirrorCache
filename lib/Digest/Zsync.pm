package Digest::Zsync;

use Mojo::Base -base, -signatures;
use Digest::MD4;
use Data::Dumper;
use bytes;

has 'block_size' => 2048;
has seq_matches => 1;
has rsum_len => 2;
has checksum_len => 3;
has 'hashes';

sub digest ($self) {
    my $arr = $self->hashes;
    my @arr = @$arr;
    join '', @arr;
}

sub init ($self, $size) {
    $self->block_size(4096)   if $size > 1024*1024*4;
    $self->block_size(2*4096) if $size > 1024*1024*1024;
    $self->block_size(4*4096) if $size > 1024*1024*1024*16;

    $self->seq_matches(2) if $size >= $self->block_size;
    my $rsum_len = int(0.99 + ((log($size // 1) + log($self->block_size)) / log(2) - 8.6) / $self->seq_matches / 8);
    $rsum_len = 4 if $rsum_len > 4;
    $rsum_len = 2 if $rsum_len < 2;
    $self->rsum_len($rsum_len);
    my $checksum_len = int(0.99 +
                (20 + (log($size // 1) + log(1 + $size / $self->block_size)) / log(2))
                / $self->seq_matches / 8);

    my $checksum_len2 = int((7.9 + (20 + log(1 + $size / $self->block_size) / log(2))) / 8);
    $checksum_len = $checksum_len2 if $checksum_len < $checksum_len2;
    $self->checksum_len($checksum_len);

    my @hashes;
    $self->hashes(\@hashes);

    return $self;
}

sub add($self, $data) {
    my $zhashes = $self->hashes;
    my $block_size = $self->block_size;
    use bytes;
    while (length($data)) {
        (my $block, $data) = unpack("a${block_size}a*", $data);
        my $diff = $self->block_size - length($block);
        $block .= (chr(0) x $diff) if $diff;
        push @$zhashes, zsync_rsum06($block, $block_size, $self->rsum_len);
        push @$zhashes, substr(Digest::MD4::md4($block),0,$self->checksum_len);
    }
    no bytes;
    return $self;
}

sub lengths($self) {
    return $self->seq_matches . ',' . $self->rsum_len . ',' . $self->checksum_len;
}

use Inline C => <<'EOC';
struct rsum {
    unsigned short	a;
    unsigned short	b;
} __attribute__((packed));

SV* zsync_rsum06(char* data, size_t len, size_t x) {
    register unsigned short a = 0;
    register unsigned short b = 0;
    while (len) {
        unsigned char c = *data++;
        a += c;
        b += len * c;
        len--;
    }
    struct rsum r = { htons(a), htons(b) };
    char* buffer = (char*)&r;

    return newSVpv(buffer + 4-x, x);
}
EOC


1;
