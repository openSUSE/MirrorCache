use utf8;
package MirrorCache::Schema;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Schema';

__PACKAGE__->load_namespaces;


# Created by DBIx::Class::Schema::Loader v0.07049 @ 2020-06-24 15:20:56
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:EdFAN9vLCRPN7CD/CZgt0A


# You can replace this text with custom code or comments, and it will be preserved on regeneration

__PACKAGE__->load_namespaces;

my $SINGLETON;

sub connect_db {
    my %args  = @_;
    my $check = $args{check};
    $check //= 1;

    unless ($SINGLETON) {

        # my $mode = $args{mode} || $ENV{MIRRORCACHE_DATABASE} || 'production';
        # if ($mode eq 'test') {
            $SINGLETON = __PACKAGE__->connect($ENV{TEST_PG});
        # }
    }

    return $SINGLETON;
}

sub disconnect_db {
    if ($SINGLETON) {
        $SINGLETON->storage->disconnect;
        $SINGLETON = undef;
    }
}

sub dsn {
    my $self = shift;
    return $self->storage->connect_info->[0]->{dsn};
}

sub singleton { $SINGLETON || connect_db() }

sub _try_deploy_db {
    my ($dh) = @_;

    my $schema = $dh->schema;
    my $version;
    try {
        $version = $dh->version_storage->database_version;
    }
    catch {
        $dh->install;
        $schema->create_system_user;    # create system user right away
    };

    return !$version;
}

sub _try_upgrade_db {
    my ($dh) = @_;

    my $schema = $dh->schema;
    if ($dh->schema_version > $dh->version_storage->database_version) {
        $dh->upgrade;
        return 1;
    }

    return 0;
}

1;
