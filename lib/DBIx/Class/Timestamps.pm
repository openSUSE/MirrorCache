package DBIx::Class::Timestamps;

use strict;
use warnings;

use base 'DBIx::Class';

use DateTime::HiRes;
use Exporter 'import';

our @EXPORT_OK = qw(now);

sub add_timestamps {
    my $self = shift;

    $self->load_components(qw(InflateColumn::DateTime DynamicDefault));

    $self->add_columns(
        t_created => {
            data_type                 => 'timestamp',
            dynamic_default_on_create => 'now'
        },
        t_updated => {
            data_type                 => 'timestamp',
            dynamic_default_on_create => 'now',
            dynamic_default_on_update => 'now'
        },
    );
}

sub now {
    DateTime::HiRes->now(time_zone => 'local');
}

1;
