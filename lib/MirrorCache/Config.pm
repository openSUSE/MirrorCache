# Copyright (C) 2022-2024 SUSE LLC
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
has root_nfs     => $ENV{MIRRORCACHE_ROOT_NFS};
has dbuser       => $ENV{MIRRORCACHE_DBUSER};
has dbpass       => $ENV{MIRRORCACHE_DBPASS};
has dbhost       => $ENV{MIRRORCACHE_DBHOST};
has dbport       => $ENV{MIRRORCACHE_DBPORT};
has dbdb         => $ENV{MIRRORCACHE_DB} // 'mirrorcache';
has dsn          => $ENV{MIRRORCACHE_DSN};
has redirect     => $ENV{MIRRORCACHE_REDIRECT};
has redirect_vpn => $ENV{MIRRORCACHE_REDIRECT_VPN};
has vpn_prefix   => $ENV{MIRRORCACHE_VPN_PREFIX};

has 'offline_redirect'; # list of url to fallback if there was an error while serving from DB
has 'offline_redirect_https'; # the same as above, just with https

has redirect_huge  => $ENV{MIRRORCACHE_REDIRECT_HUGE};
has huge_file_size => int($ENV{MIRRORCACHE_HUGE_FILE_SIZE} // 0) || 40*1024*1024;
has small_file_size => int($ENV{MIRRORCACHE_SMALL_FILE_SIZE} // 0);

has city_mmdb     => $ENV{MIRRORCACHE_CITY_MMDB};
has ip2location   => $ENV{MIRRORCACHE_IP2LOCATION};
has top_folders   => $ENV{MIRRORCACHE_TOP_FOLDERS};

has plugin_status => $ENV{MIRRORCACHE_PLUGIN_STATUS};

has regions               => $ENV{MIRRORCACHE_REGIONS};
has mirror_provider       => $ENV{MIRRORCACHE_MIRROR_PROVIDER};

has db_provider           => undef;
has custom_footer_message => $ENV{MIRRORCACHE_CUSTOM_FOOTER_MESSAGE};

has browser_agent_mask => $ENV{MIRRORCACHE_BROWSER_AGENT_MASK} // '(?i)(firefox|msie|chrom|safari|seamonkey|opera|opr|trident).*';
has country_image_dir => $ENV{MIRRORCACHE_COUNTRY_IMAGE_DIR} // '/srv/www/htdocs/webalizer/flags/';

has geoip => undef;

sub init($self, $cfgfile) {
    my $db_provider = $ENV{MIRRORCACHE_DB_PROVIDER};

    my $cfg;
    $cfg = Config::IniFiles->new(-file => $cfgfile, -fallback => 'default') if $cfgfile;
    if ($cfg) {
        for my $k (qw/root root_nfs redirect redirect_huge huge_file_size small_file_size city_mmdb ip2location top_folders regions mirror_provider browser_agent_mask custom_footer_message country_image_dir vpn_prefix/) {
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
            $db_provider = $v;
        }
        if (my $v = $cfg->val('db', 'dsn')) {
            $self->dsn($v);
        }
        if (my $v = $cfg->val('plugin', 'status')) {
            $self->plugin_status($v);
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

    my ($offline_redirect, @offline_redirect, @offline_redirect_https);
    $offline_redirect = $cfg->val('default', 'offline_redirect') if $cfg;
    $offline_redirect = $ENV{MIRRORCACHE_OFFLINE_REDIRECT} unless $offline_redirect;

    if ($offline_redirect) {
        for my $m (split /[\s]+/, $offline_redirect) {
            push @offline_redirect,       'http://'  . $m;
            push @offline_redirect_https, 'https://' . $m;
        }
        $self->offline_redirect(\@offline_redirect);
        $self->offline_redirect_https(\@offline_redirect_https);
    }

    my %geoip;
    foreach (sort keys %ENV) {
        my (undef, $reg) = split /MIRRORCACHE_GEOIP_(.*)/, $_;
        next unless $reg;
        $geoip{lc($reg)} = $ENV{$_};
    }
    if ($cfg) {
        my @param = $cfg->Parameters('default');
        for my $k (@param) {
            my (undef, $reg) = split /geoip_(.*)/, $k;
            next unless $reg;
            $geoip{lc($reg)} = $cfg->val('default', $k);
        }
    }

    $self->geoip(\%geoip);
    if (my $country_image_dir = $self->country_image_dir) {
        ( -d $country_image_dir && -r $country_image_dir ) or $self->country_image_dir('');
    }

    return 1;
}

1;
