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

sub singleton { state $root = shift->SUPER::new; return $root; };

my $rootpath;
my $app;

sub register {
    (my $self, $app) = @_;
    $rootpath = $app->mc->rootlocation;
    push @{$app->static->paths}, $rootpath;
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
    return -f $rootpath . $_[1];
}

sub is_dir {
    return 1 unless $_[1];
    return -d $rootpath . $_[1];
}

sub render_file {
    my ($self, $dm, $filepath, $not_miss) = @_;
    my $c = $dm->c;
    my $res = !!$c->reply->static($filepath);
    $c->stat->redirect_to_root($dm, $not_miss);
    return $res;
}

sub foreach_filename {
    my $self = shift;
    my $dir  = shift;
    my $sub  = shift;
    Mojo::File->new($rootpath . $dir)->list({dir => 1})->each(sub {
            my $f = shift;
            my $stat = $f->stat;
            $sub->($f->basename, $stat->size, $stat->mode, $stat->mtime);
        });
    return 1;
}

sub list_filenames {
    my $self    = shift;
    my $dir = shift || return [];
    my @files;
    my $cb = sub {
        my $f = shift;
        next if $f eq '.' or $f eq '..';
        push @files, Encode::decode_utf8($f);
    };
    $self->foreach_filename($dir, $cb);
    return \@files;
}

1;
