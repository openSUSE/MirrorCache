# Copyright (C) 2022 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License

package MirrorCache::Config;

use Mojo::Base -base, -signatures;

use Config::IniFiles;

# Using ENV variables is overall fine,
# except when it is needed to change them and reload hypnotoad service without downtime.
#
# For those values which may change it is better to use config file (the rest may be moved here as well)

has root         => $ENV{MIRRORCACHE_ROOT};
has dbuser       => $ENV{MIRRORCACHE_DBUSER};
has dbpass       => $ENV{MIRRORCACHE_DBPASS};
has dbhost       => $ENV{MIRRORCACHE_DBHOST};
has dbport       => $ENV{MIRRORCACHE_DBPORT};
has dbdb         => $ENV{MIRRORCACHE_DB} // 'mirrorcache';
has dsn          => $ENV{MIRRORCACHE_DSN};
has dsn_replica  => $ENV{MIRRORCACHE_DSN_REPLICA};
has redirect     => $ENV{MIRRORCACHE_REDIRECT};
has redirect_vpn => $ENV{MIRRORCACHE_REDIRECT_VPN};

has db_provider           => undef;
has custom_footer_message => $ENV{MIRRORCACHE_CUSTOM_FOOTER_MESSAGE};

sub init($self, $cfgfile) {
    my $db_provider = $ENV{MIRRORCACHE_DB_PROVIDER};

    my $cfg;
    $cfg = Config::IniFiles->new(-file => $cfgfile, -fallback => 'default') if $cfgfile;
    if ($cfg) {
        for my $k (qw/root redirect/) {
            if (my $v = $cfg->val('default', $k)) {
                $self->$k($v);
            }
        }
        for my $k (qw/user pass host port db/) {
            if (my $v = $cfg->val('db', $k)) {
                my $fn = "db$k";
                $self->$fn($v);
            }
        }
        if (my $v = $cfg->val('db', 'provider')) {
            $self->db_provider($v);
        }
        if (my $v = $cfg->val('db', 'dsn')) {
            $self->dsn($v);
        }
    }

    $db_provider = 'mysql' if !$db_provider && $ENV{TEST_MYSQL};
    $db_provider = 'postgresql' unless $db_provider;
    $db_provider = 'Pg'    if $db_provider eq 'postgresql';
    $db_provider = 'mysql' if $db_provider eq 'mariadb';

    my $db   = $self->dbdb;
    my $port = $self->dbport;

    my $dsn;
    if ($ENV{TEST_PG}) {
        $dsn = $ENV{TEST_PG};
        $db_provider = 'Pg';
    } elsif ($ENV{TEST_MYSQL}) {
        $dsn = $ENV{TEST_MYSQL};
        $db_provider = 'mysql';
    } elsif ($self->dsn) {
        $dsn = $self->dsn;
    } else {
        my $host = $self->dbhost;
        $dsn  = "DBI:$db_provider:dbname=$db";
        $dsn = "$dsn;host=$host" if $host;
        $dsn = "$dsn;port=$port" if $port;
    }

    $self->db_provider($db_provider);
    $self->dsn($dsn);

    if ($ENV{MIRRORCACHE_DBREPLICA}) {
        my $dsn_replica;
        my $host = $ENV{MIRRORCACHE_DBREPLICA};
        $dsn_replica = "DBI:$db_provider:dbname=$db";
        $dsn_replica = "$dsn_replica;host=$host" if $host;
        $dsn_replica = "$dsn_replica;port=$port" if $port;
        $self->dsn_replica($dsn_replica);
    }

    return 1;
}

1;
