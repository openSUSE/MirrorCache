# Copyright (C) 2020 SUSE LLC
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

package MirrorCache::WebAPI::Plugin::RootLocal;
use Mojo::Base 'Mojolicious::Plugin';

use Encode ();
use DirHandle;
use Mojolicious::Types;

use constant { dir=>0, host=>1, host_vpn=>2 };

sub singleton { state $root = shift->SUPER::new; return $root; };

my @roots;
my $app;

sub register {
    (my $self, $app) = @_;
    my $rootpath = $app->mc->rootlocation;
    for my $part (split /\|/, $rootpath) {
        my ($dir, $host, $host_vpn) = (split /:/, $part, 3);
        my @root = ( $dir, $host, $host_vpn );
        push @roots, \@root;
        push @{$app->static->paths}, $dir;
    }

    $app->helper( 'mc.root' => sub { $self->singleton; });
}

sub is_remote {
    return 0;
}

sub is_reachable {
    return 1;
}

sub is_file {
    return 1 unless $_[1];
    for my $root (@roots) {
        return 1 if -f $root->[dir] . $_[1];
    }
    return 0;
}

sub is_dir {
    return 1 unless $_[1];
    for my $root (@roots) {
        return 1 if -d $root->[dir] . $_[1];
    }
    return 0;
}

sub render_file {
    my ($self, $dm, $filepath, $not_miss) = @_;
    my $c = $dm->c;
    my $redirect = $self->redirect($dm, $filepath);
    my $res;
    if ($redirect) {
        $res = !!$c->redirect_to($redirect);
    } else {
        $res = !!$c->reply->static($filepath);
    }
    $c->stat->redirect_to_root($dm, $not_miss);
    return $res;
}

sub redirect {
    my ($self, $dm, $filepath) = @_;
    $filepath = "" unless $filepath;
    for my $root (@roots) {
        next unless -e $root->[dir] . $filepath;

        return $dm->scheme . "://" . $root->[host_vpn] if ($dm->vpn && $root->[host_vpn]);
        return $dm->scheme . "://" . $root->[host] if ($root->[host]);
        return undef;
    }
    return undef;
}

sub foreach_filename {
    my $self = shift;
    my $dir  = shift;
    my $sub  = shift;
    for my $root (@roots) {
        next unless -d $root->[dir] . $dir;
        Mojo::File->new($root->[dir] . $dir)->list({dir => 1})->each(sub {
            my $f = shift;
            my $stat = $f->stat;
            $sub->($f->basename, $stat->size, $stat->mode, $stat->mtime);
        });
    }
    return 1;
}

sub list_files {
    my $self = shift;
    my $dir  = shift;

    my @files;
    for my $root (@roots) {
        next unless -d $root->[dir] . $dir;
        Mojo::File->new($root->[dir] . $dir)->list({dir => 1})->each(sub {
            my $f = shift;
            push @files, $f;
        });
    }
    return \@files;
}

1;
