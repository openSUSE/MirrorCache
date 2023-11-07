# Copyright (C) 2020,2021 SUSE LLC
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

use Cwd;

use constant { dir=>0, host=>1, host_vpn=>2 };

my @roots;
my $app;

my $root_subtree = $ENV{MIRRORCACHE_SUBTREE} // "";

has 'urlredirect';
has 'urlredirect_huge';
has 'huge_file_size';
has 'top_folders';

my %TOP_FOLDERS;

sub register {
    (my $self, $app) = @_;
    my $rootpath = $app->mc->rootlocation;
    for my $part (split /\|/, $rootpath) {
        my ($dir, $host, $host_vpn) = (split /:/, $part, 3);
        my @root = ( $dir, $host, $host_vpn );
        push @roots, \@root;
    }

    $self->urlredirect($app->mcconfig->redirect);
    $self->urlredirect_huge($app->mcconfig->redirect_huge);
    $self->huge_file_size($app->mcconfig->huge_file_size);
    $self->top_folders($app->mcconfig->top_folders);
    my $top_folders=$app->mcconfig->top_folders;
    if ($top_folders) {
        for my $folder (split(' ', $top_folders)) {
            $TOP_FOLDERS{$folder} = 1;
        }
    }

    $app->helper( 'mc.root' => sub { $self; });
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
        return 1 if -f $root->[dir] . $root_subtree . $_[1];
    }
    return 0;
}

sub is_dir {
    my ($self, $path) = @_;
    return 1 if !$path || $path eq '/';
    for my $root (@roots) {
        return 1 if -d $root->[dir] . $root_subtree . $path;
    }
    return 0;
}

sub render_file {
    my ($self, $dm, $filepath, $not_miss) = @_;
    my $realpath = $self->realpath($filepath) unless $root_subtree;
    $filepath = $realpath if $realpath;
    my $c = $dm->c;
    my $redirect = $self->redirect($dm, $filepath);
    my $res;
    if ($redirect) {
        $res = !!$c->redirect_to($redirect . $root_subtree . $filepath);
    } else {
        my $rootpath = $self->rootpath($filepath);
        return !!$c->render(status => 404, text => "File $filepath not found") unless $rootpath;
        $res = !!$c->render_file(filepath => $rootpath . $root_subtree . $filepath, content_type => $dm->mime, content_disposition => 'inline');
    }
    $c->stat->redirect_to_root($dm, $not_miss);
    return $res;
}

sub render_file_if_small {
    my ($self, $dm, $file, $max_size) = @_;

    my $full = $self->rootpath($file);
    return undef unless $full;
    $full = $full . $root_subtree . $file;

    my $size;
    eval { $size = -s $full if -f $full; };
    return undef unless ((defined $size) && $size <= $max_size);
    my $c = $dm->c;
    $c->render_file(filepath => $full, content_type => $dm->mime, content_disposition => 'inline');
    return 1;
}

sub redirect {
    my ($self, $dm, $filepath) = @_;
    $filepath = "" unless $filepath;
    for my $root (@roots) {
        next unless ( -e $root->[dir] . $root_subtree . $filepath || ( $root_subtree && ( -e $root->[dir] . $filepath  ) ) );
        if ($self->urlredirect_huge) {
            my $size = -s $root->[dir] . $filepath;
            return $dm->scheme . "://" . $self->urlredirect_huge if (($size // 0) >= $self->huge_file_size);
        }

        return $dm->scheme . "://" . $root->[host_vpn] if ($dm->vpn && $root->[host_vpn]);
        return $dm->scheme . "://" . $root->[host] if ($root->[host]);
        return $dm->scheme . "://" . $self->urlredirect if ($self->urlredirect);
        last;
    }
    return undef;
}

sub realpath {
    my ($self, $path) = @_;
    return undef unless $path;

    my $rootpath = $self->rootpath($path);
    return undef unless $rootpath;
    my $localpath = $rootpath . $root_subtree . $path;
    my $realpathlocal = Cwd::realpath($localpath);

    if ($realpathlocal && (0 == rindex($realpathlocal, $rootpath, 0))) {
        my $realpath = substr($realpathlocal, length($rootpath));
        return $realpath if $realpath ne $path;
    }
    return undef;
}


sub rootpath {
    my ($self, $filepath) = @_;
    $filepath = "" unless $filepath;
    for my $root (@roots) {
        return $root->[dir] if -e $root->[dir] . $root_subtree . $filepath;
    }
    return undef;
}



sub _detect_ln_in_the_same_folder {
    my ($dir, $file) = @_;
    return undef unless $file;

    my $dest;
    for my $root (@roots) {
        eval {
            $dest = readlink($root->[dir] . $dir . '/' . $file);
        };
        next unless $dest;
        $dest = Mojo::File->new($dest);

        return undef unless $dest->dirname eq '.' || $dest->dirname eq $dir;
        return $dest->basename;
    };
    return undef;
}

sub detect_ln_in_the_same_folder {
    my ($self, $path) = @_;
    my $f = Mojo::File->new($path);
    my $res = _detect_ln_in_the_same_folder($f->dirname, $f->basename);
    return undef unless $res;
    return $f->dirname . '/' . $res;
}

# we cannot use $subtree here, because we may actually render from realdir, which is outside subtree
sub foreach_filename {
    my $self = shift;
    my $dir  = shift;
    my $sub  = shift;
    my $P    = shift;
    for my $root (@roots) {
        next unless -d $root->[dir] . $dir;
        Mojo::File->new($root->[dir] . $dir)->list({dir => 1})->each(sub {
            my $f = shift;
            next if $P && $f->basename !~ $P;
            my $stat = $f->stat;
            if ($stat) {
                if (($dir eq '/' || $dir eq $root_subtree) && %TOP_FOLDERS) {
                    if (-d $f) {
                        return undef unless $TOP_FOLDERS{$f->basename};
                    }
                }
                my $target = _detect_ln_in_the_same_folder($dir, $f->basename);
                $sub->($f->basename, $stat->size, $stat->mode, $stat->mtime, $target),
            } else {
                $sub->($f->basename, undef, undef, undef);
            }
        });
    }
    return 1;
}

# we cannot use $subtree here, because we may actually render from realdir, which is outside subtree
sub list_files {
    my $self = shift;
    my $dir  = shift;
    my $re1  = shift;
    my $re2  = shift;

    my @files;
    for my $root (@roots) {
        next unless -d $root->[dir] . $dir;
        Mojo::File->new($root->[dir] . $dir)->list({dir => 1})->each(sub {
            my $f = shift;
            return undef if $re1 && $f->basename !~ /$re1/;
            return undef if $re2 && $f->basename !~ /$re2/;
            if (($dir eq '/' || $dir eq $root_subtree) && %TOP_FOLDERS) {
                if (-d $f) {
                    return undef unless $TOP_FOLDERS{$f->basename};
                }
            }
            push @files, $f;
        });
    }
    return \@files;
}

1;
