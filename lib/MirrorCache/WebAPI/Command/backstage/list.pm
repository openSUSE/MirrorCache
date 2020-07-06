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
# with this program; if not, see <http://www.gnu.org/licenses/>.

package MirrorCache::WebAPI::Command::backstage::list;
use Mojo::Base 'Minion::Command::backstage::job';

has description => 'List Minion jobs';
has usage       => sub { shift->extract_usage };

1;

=encoding utf8

=head1 NAME

MirrorCache::WebAPI::Command::backstage::list - Gru list command

=head1 SYNOPSIS

  Usage: APPLICATION backstage list [OPTIONS] [IDS]

    script/mirrorcache backstage list

  Options:
    See 'script/mirrorcache backstage job -h' for all available options.

=head1 DESCRIPTION

L<MirrorCache::WebAPI::Command::backstage::list> is a subclass of
L<Minion::Command::backstage::job> that merely renames the command for backwards
compatibility.

=cut
