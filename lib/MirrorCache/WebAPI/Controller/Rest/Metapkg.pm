# Copyright (C) 2024 SUSE LLC
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

package MirrorCache::WebAPI::Controller::Rest::Metapkg;
use Mojo::Base 'Mojolicious::Controller';

sub index {
    my ($self) = @_;
    my $name = $self->param("name");
    return $self->render(code => 400, text => "Mandatory argument {name} is missing") unless $name;

    my $pkg = $self->schema->resultset('Metapkg')->find({ name => $name });

    $self->render(json => {$pkg->get_columns});
}

sub search_locations {
    my ($self) = @_;

    my $package    = $self->param('package');

    return $self->render(code => 400, text => "Mandatory argument {package} is missing") unless $package;

    my $p_official = $self->param('official');
    my $p_os       = $self->param('os');
    my $p_os_ver   = $self->param('os_ver');
    my $p_repo     = $self->param('repo');

    my $sql_from = <<'END_SQL';
select metapkg.name, folder.path as path, file.name as file, file.size as size, file.mtime as time
from metapkg
join pkg on metapkg_id = metapkg.id
join folder on pkg.folder_id = folder.id
left join file on file.folder_id = pkg.folder_id and file.name like concat(metapkg.name, '-%')
END_SQL

    my @parms;
    my $arch = '';

    if (my $p = $self->param('arch')) {
        $arch = "%$p";
    }


    if ($p_official) {
        $sql_from  = $sql_from . "\njoin project on folder.path like concat(project.path, '%') and project.prio > 10\n";
    }
    if ($p_os) {
        $sql_from  = $sql_from . "\njoin popular_os os on folder.path ~ os.mask and (coalesce(os.neg_mask,'') = '' or not folder.path ~ os.neg_mask) and os.name = ?\n";
        push @parms, $p_os;
        if ($p_os_ver) {
            $sql_from = "$sql_from and ? = coalesce(regexp_replace(folder.path, os.mask, os.version))";
            push @parms, $p_os_ver;
        }
    }

    my $sql_where = "WHERE file.name like ? and metapkg.name = ?";

    push @parms, "$package$arch%";
    push @parms, "$package";
    if ($p_repo) {
        $sql_where = "$sql_where and folder.path like concat('%/', ?::text, '/', ?::text)";
        push @parms, $p_repo;
        push @parms, ($arch ? $arch : '%');
    }

    my $sql = $sql_from . "\n"  . $sql_where;

    unless ($self->schema->pg) {
        $sql =~ s/ ~ / RLIKE /g;
        $sql =~ s/::text//g;
    }
    my $res = $self->schema->storage->dbh->selectall_arrayref($sql, {Columns => {}}, @parms);

    return $self->render(json => { data => $res });
}

sub search {
    my ($self) = @_;

    my $package    = $self->param('package');
    my $p_official = $self->param('official');
    my $p_os       = $self->param('os');
    my $p_os_ver   = $self->param('os_ver');
    my $p_repo     = $self->param('repo');

    my $sql_from = <<'END_SQL';
select distinct metapkg.name
from metapkg
join pkg on metapkg_id = metapkg.id
END_SQL

    my $sql_where = "WHERE metapkg.name like ?";
    my @parms;
    my $arch = '';

    if (my $p = $self->param('arch')) {
        $arch = "%$p";
    }

    if ($p_official || $p_os || $p_repo) {
        $sql_from = "$sql_from\njoin folder on pkg.folder_id = folder.id";
    }

    # and file.name like concat(metapkg.name, '-%')

    if ($p_official) {
        $sql_from  = $sql_from . "\njoin project on folder.path like concat(project.path, '%') and project.prio > 10\n";
    }
    if ($p_os) {
        $sql_from  = $sql_from . "\njoin popular_os os on folder.path ~ os.mask and (coalesce(os.neg_mask,'') = '' or not folder.path ~ os.neg_mask) and os.name = ?\n";
        push @parms, $p_os;
        if ($p_os_ver) {
            $sql_from = "$sql_from and ? = coalesce(regexp_replace(folder.path, os.mask, os.version))";
            push @parms, $p_os_ver;
        }
    }
    push @parms, "$package%";
    if ($p_repo) {
        $sql_where = "$sql_where and folder.path like concat('%/', ?::text, '/', ?::text)";
        push @parms, $p_repo;
        push @parms, ($arch ? $arch : '%');
    }

    my $sql = $sql_from . "\n"  . $sql_where;

    unless ($self->schema->pg) {
        $sql =~ s/ ~ / RLIKE /g;
        $sql =~ s/::text//g;
    }

    my $res = $self->schema->storage->dbh->selectall_arrayref($sql, {Columns => {}}, @parms);
    return $self->render(json => { data => $res });
}

1;
