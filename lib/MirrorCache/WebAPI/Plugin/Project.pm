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
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

package MirrorCache::WebAPI::Plugin::Project;
use Mojo::Base 'Mojolicious::Plugin';

use Mojo::JSON qw(decode_json encode_json);

my $initialized = 0;
my @projects;
my %projects_path;
my %projects_alias;
my %projects_redirect;
my %projects_region_redirect;
my %projects_shard;

my $last_init_warning;

my $caching   = 1;
my $cache_dir = '.cache';
my $cache_filename = 'project';

sub register {
    my ($self, $app) = @_;

    $app->helper('mcproject.list' => \&_list);
    $app->helper('mcproject.get_id' => \&_get_id);
    $app->helper('mcproject.list_full' => \&_list_full);
    $app->helper('mcproject.redirect' => \&_redirect);
    $app->helper('mcproject.caching' => \&_caching);
    $app->helper('mcproject.cache_dir' => \&_cache_dir);
    $app->helper('mcproject.shard_for_path' => \&_shard_for_path);

    $caching = 0 unless -w $cache_dir;

    return $self;
}

sub _init_if_needed {
    return 1 if $initialized;
    my ($c) = @_;
    my $wasdberror = 1;
    my $err = 'Unknown';
    eval { #the table may be missing - no big deal (only reports might be inaccurate if some other error occurred).
        eval {
            my @rows = $c->schema->resultset('Project')->search(undef, { order_by => { -desc => [qw/prio name/] } });
            my @projs;
            # we want to cache it, so move to simpler structure
            for my $r (@rows) {
                my %proj = ( id => $r->id, name => $r->name, path => $r->path, redirect => $r->redirect, prio => $r->prio, shard => $r->shard );
                push @projs, \%proj;
            }
            @projects = @projs;
            $wasdberror = 0;
            $initialized = 1;
        };
        $err = $@;
        if ($wasdberror && !@projects) {
            my $f = Mojo::File->new( "$cache_dir/$cache_filename.json" );
            if (-r $f) {
                eval {
                    my $body = $f->slurp;
                    my $json = decode_json($body);
                    @projects = @$json;
                    $c->log->error($c->dumper("Loaded projects from cache", \@projects));
                    $initialized = 1;
                };
            }
        }
        1;
    };
    if ($wasdberror) {
        if (!$last_init_warning || 600 < time() - $last_init_warning) {
            $c->log->error($c->dumper("Cannot load projects", $err));
            $last_init_warning = time();
        }
        return 0 unless $initialized;
    };

    if ($caching && @projects && !$wasdberror) {
        eval {
            my $f = Mojo::File->new( "$cache_dir/$cache_filename.json" );
            $f->spew(encode_json([ @projects ]));
        };
    }

    for my $p (@projects) {
        my $name  = $p->{name};
        my $id    = $p->{id};
        my $alias = $name;
        $alias =~ tr/ //ds;  # remove spaces
        $alias =~ tr/\.//ds; # remove dots
        $alias = "c$alias" if $alias =~ /^\d/;
        $alias = lc($alias);
        $projects_path{$name} = $p->{path};
        $projects_path{$id}   = $p->{path};
        $projects_alias{$name} = $alias;
        if (my $shard = $p->{shard}) {
            $projects_shard{$p->{path}} = $shard;
        }
        my $redirect = $p->{redirect};
        next unless $redirect;
        my @parts = split ';', $redirect;
        for my $r (@parts) {
            my $prefix = substr($r,0,3);
            my $c = chop($prefix);
            if (':' eq $c) {
                $projects_region_redirect{$prefix}{$name} = substr($r,3);
            } else {
                $projects_redirect{$name} = $r;
            }
        }
    }
}

sub _list {
    my ($c) = @_;
    _init_if_needed($c);

    my @res;
    for my $p (@projects) {
        push @res, $p->{name};
    }
    return \@res;
}

sub _list_full {
    my ($c) = @_;
    _init_if_needed($c);

    my @res;
    for my $p (@projects) {
        my $name  = $p->{name};
        my $alias = $projects_alias{$name};
        my $path  = $projects_path{$name};

        my %prj = ( id => $p->{id}, name => $name, alias => $alias, path => $path, prio => $p->{prio} );
        push @res, \%prj;
    }
    return \@res;
}

sub _redirect {
    my ($c, $path, $region) = @_;
    _init_if_needed($c);

    for my $p (@projects) {
        my $name  = $p->{name};
        my $redirect;
        $redirect = $projects_region_redirect{$region}{$name} if $region;
        $redirect = $projects_redirect{$name} unless $redirect;
        next unless $redirect;
        my $ppath  = $projects_path{$name};
        return $redirect if (0 == rindex($path, $ppath, 0));
    }
    return '';
}

sub _get_id {
    my ($c, $path) = @_;
    _init_if_needed($c);

    for my $p (@projects) {
        my $id = $p->{id};
        my $ppath  = $projects_path{$id};
        return $id if (0 == rindex($path, $ppath, 0));
    }
    return '';
}

sub _caching {
    $caching;
}

sub _cache_dir {
    $cache_dir;
}

sub _shard_for_path {
    my ($c, $path) = @_;
    _init_if_needed($c);
    return '' unless keys %projects_shard;

    $path = substr($path, 0, index($path, '/', 1));
    return $projects_shard{$path};
}

1;
