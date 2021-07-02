use utf8;
package MirrorCache::Schema;

use strict;
use warnings;

use base 'DBIx::Class::Schema';
use Mojo::File qw(path);
use Mojo::Pg;

__PACKAGE__->load_namespaces;

my $SINGLETON;

sub connect_db {
    my %args  = @_;

    unless ($SINGLETON) {
        my $dsn;
        my $user = $ENV{MIRRORCACHE_DBUSER};
        my $pass = $ENV{MIRRORCACHE_DBPASS};
        if ($ENV{TEST_PG}) {
            $dsn = $ENV{TEST_PG};
        } elsif ($ENV{MIRRORCACHE_DSN}) {
            $dsn = $ENV{MIRRORCACHE_DSN};
        } else {
            my $db   = $ENV{MIRRORCACHE_DB} // 'mirrorcache';
            my $host = $ENV{MIRRORCACHE_DBHOST};
            my $port = $ENV{MIRRORCACHE_DBPORT};
            $dsn  = "DBI:Pg:dbname=$db";
            $dsn = "$dsn;host=$host" if $host;
            $dsn = "$dsn;port=$port" if $port;
        }
        $SINGLETON = __PACKAGE__->connect($dsn, $user, $pass);
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
    my $ci = $self->storage->connect_info->[0];
    if ( $ci eq 'HASH' ) {
        return $ci->{dsn}
    }
    return $ci;
}

sub singleton { $SINGLETON || connect_db() }

sub has_table {
    my ($self,$table_name) = @_;

    my $sth = $self->storage->dbh->table_info(undef, 'public', $table_name, 'TABLE');
    $sth->execute;
    my @info = $sth->fetchrow_array;

    my $exists = scalar @info;
    return $exists;
}

sub migrate {
    my $self = shift;
    my $conn = Mojo::Pg->new;
    $conn->dsn( $self->dsn );
    $conn->password($ENV{MIRRORCACHE_DBPASS}) if $ENV{MIRRORCACHE_DBPASS};

    my $dbh     = $self->storage->dbh;
    my $dbschema = path(__FILE__)->dirname->child('resources', 'migrations', 'pg.sql');
    $conn->auto_migrate(1)->migrations->name('mirrorcache')->from_file($dbschema);
    $conn->db; # this will do migration
}

1;
