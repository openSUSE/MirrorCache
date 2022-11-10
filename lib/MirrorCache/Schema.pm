use utf8;
package MirrorCache::Schema;

use strict;
use warnings;

use base 'DBIx::Class::Schema';
use Mojo::File qw(path);
# use Mojo::Pg;
# use Mojo::mysql;

__PACKAGE__->load_namespaces;

my $SINGLETON;
my $SINGLETONR;

my $PROVIDER;

sub pg {
    return 1 if $PROVIDER eq 'Pg';
    return 0;
}

sub provider {
    return $PROVIDER;
}

sub connect_db {
    my ($self, $provider, $dsn, $user, $pass) = @_;

    $PROVIDER = $provider;

    unless ($SINGLETON) {
        if (pg()) {
            require Mojo::Pg;
        } else {
            require 'Mojo/' . $PROVIDER . '.pm';
        }

        $SINGLETON = __PACKAGE__->connect($dsn, $user, $pass);
    }

    return $SINGLETON;
}

sub connect_replica {
    my ($self, $provider, $dsn, $user, $pass) = @_;

    unless ($SINGLETONR) {
        $SINGLETONR = __PACKAGE__->connect($dsn, $user, $pass);
    }

    return $SINGLETONR;
}

sub disconnect_db {
    if ($SINGLETON) {
        $SINGLETON->storage->disconnect;
        $SINGLETON = undef;
    }
    if ($SINGLETONR) {
        $SINGLETONR->storage->disconnect;
        $SINGLETONR = undef;
    }
}

sub dsn {
    my $self = shift;
    my $ci = $self->storage->connect_info->[0];
    if ( $ci eq 'HASH' ) {
        return $ci->{dsn}
    }
    return $ci;
}

sub singleton { $SINGLETON }

sub singletonR {
     return $SINGLETONR if $SINGLETONR;
     return singleton();
}

sub has_table {
    my ($self,$table_name) = @_;

    my $sth = $self->storage->dbh->table_info(undef, 'public', $table_name, 'TABLE');
    $sth->execute;
    my @info = $sth->fetchrow_array;

    my $exists = scalar @info;
    return $exists;
}

sub migrate {
    my ($self, $pass) = @_;
    my $conn = "Mojo::$PROVIDER"->new;
    $conn->dsn( $self->dsn );
    $conn->password($pass) if $pass;

    my $dbh     = $self->storage->dbh;
    my $dbschema = path(__FILE__)->dirname->child('resources', 'migrations', "$PROVIDER.sql");
    $conn->auto_migrate(1)->migrations->name('mirrorcache')->from_file($dbschema);
    $conn->db; # this will do migration
}

1;
