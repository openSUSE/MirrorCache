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
use Data::Dumper;

my $initialized = 0;
my @projects;
my %projects_path;
my %projects_alias;
my %projects_redirect;
my %projects_region_redirect;
my $last_init_warning;

sub register {
    my ($self, $app) = @_;

    $app->helper('mcproject.list' => \&_list);
    $app->helper('mcproject.get_id' => \&_get_id);
    $app->helper('mcproject.list_full' => \&_list_full);
    $app->helper('mcproject.redirect' => \&_redirect);
    return $self;
}

sub _init_if_needed {
    return 1 if $initialized;
    my ($c) = @_;
    eval { #the table may be missing - no big deal (only reports might be inaccurate if some other error occurred).
        @projects = $c->schema->resultset('Project')->search(undef, { order_by => { -desc => [qw/prio name/] } });
        $initialized = 1;
        1;
    } or do {
        if (!$last_init_warning || 600 < time() - $last_init_warning) {
            $c->log->error(Dumper("Cannot load projects", $@));
            $last_init_warning = time();
        }
        return 0;
    };

    for my $p (@projects) {
        my $name  = $p->name;
        my $id    = $p->id;
        my $alias = $name;
        $alias =~ tr/ //ds;  # remove spaces
        $alias =~ tr/\.//ds; # remove dots
        $alias = "c$alias" if $alias =~ /^\d/;
        $alias = lc($alias);
        $projects_path{$name} = $p->path;
        $projects_path{$id}   = $p->path;
        $projects_alias{$name} = $alias;
        my $redirect = $p->redirect;
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
        push @res, $p->name;
    }
    return \@res;
}

sub _list_full {
    my ($c) = @_;
    _init_if_needed($c);

    my @res;
    for my $p (@projects) {
        my $name  = $p->name;
        my $alias = $projects_alias{$name};
        my $path  = $projects_path{$name};

        my %prj = ( name => $name, alias => $alias, path => $path );
        push @res, \%prj;
    }
    return \@res;
}

sub _redirect {
    my ($c, $path, $region) = @_;
    _init_if_needed($c);

    for my $p (@projects) {
        my $name  = $p->name;
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
        my $id = $p->id;
        my $ppath  = $projects_path{$id};
        return $id if (0 == rindex($path, $ppath, 0));
    }
    return '';
}

1;
