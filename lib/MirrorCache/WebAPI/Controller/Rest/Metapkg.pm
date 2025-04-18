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
    my $p_ign_path = $self->param('ignore_path');
    my $p_ign_file = $self->param('ignore_file');
    my $p_strict   = $self->param('strict');

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
    push @parms, $package;
    if ($p_repo) {
        $sql_where = "$sql_where and folder.path like concat('%/', ?::text, '/', ?::text)";
        push @parms, $p_repo;
        push @parms, ($arch ? $arch : '%');
    }
    if ($p_ign_path) {
        $sql_where = "$sql_where and folder.path not like concat('%', ?::text, '%')";
        push @parms, $p_ign_path;
    }
    if ($p_ign_file) {
        $sql_where = "$sql_where and file.name not like concat('%', ?::text, '%')";
        push @parms, $p_ign_file;
    }
    if ($p_strict) {
        $sql_where = "$sql_where and file.name ~ ?";
        my $qm = quotemeta($package);
        push @parms, "^$qm-([^-]+)-([^-]+)\.(x86_64|noarch|i[3-6]86|ppc64|aarch64|arm64|amd64|s390|src)";
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
    my $p_ign_path = $self->param('ignore_path');
    my $p_ign_file = $self->param('ignore_file');
    my $p_strict   = $self->param('strict');

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

    if ($p_official || $p_os || $p_repo || $p_ign_path) {
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
    if ($p_ign_path) {
        $sql_where = "$sql_where and folder.path not like concat('%', ?::text, '%')";
        push @parms, $p_ign_path;
    }
    if ($p_ign_file) {
        $sql_where = "$sql_where and metapkg.name not like concat('%', ?::text, '%')";
        push @parms, $p_ign_file;
    }

    my $sql = $sql_from . "\n"  . $sql_where;

    unless ($self->schema->pg) {
        $sql =~ s/ ~ / RLIKE /g;
        $sql =~ s/::text//g;
    }

    my $res = $self->schema->storage->dbh->selectall_arrayref($sql, {Columns => {}}, @parms);
    return $self->render(json => { data => $res });
}


sub stat_download {
    my $self = shift;
    my $id = $self->param('id');
    my $sql;
    $sql = <<'END_SQL';
select
  extract(epoch from ( select min(dt) from agg_download_pkg where metapkg_id = ? and period = 'day' ))::int as first_seen,
  coalesce( (select sum(cnt) as cnt from agg_download_pkg where metapkg_id = ? and period = 'total' and dt = (select max(dt) from agg_download_pkg where period = 'total')), 0 ) as cnt_total,
  coalesce( (select sum(cnt) as cnt from agg_download_pkg where metapkg_id = ? and period = 'hour'  and dt > (select max(dt) from agg_download_pkg where period = 'total')), 0 ) as cnt_today,
  sum(cnt) as cnt_30d,
  coalesce( sum(case when dt > now() - interval '7 day' then cnt else 0 end), 0 ) as cnt_7d,
  coalesce( sum(case when dt > now() - interval '1 day' then cnt else 0 end), 0) as cnt_1d
from agg_download_pkg
where metapkg_id = ? and period = 'day' and dt > now() - interval '30 day'
END_SQL
    unless ($self->schema->pg) {
        $sql =~ s/::int//g;
        $sql =~ s/interval '(\d+) day'/interval $1 day/g;
        $sql =~ s/extract\(epoch from/unix_timestamp(/g;
    }

    my $res = $self->schema->storage->dbh->selectall_arrayref($sql, {Columns => {}}, $id, $id, $id, $id);
    return $self->render(json => { data => $res });
}

sub stat_download_curr {
    my $self = shift;
    my $name = $self->param('name');
    my $sql;
    $sql = <<'END_SQL';
select count(*) as cnt_curr
from stat
where stat.dt > coalesce((select max(dt) as dt from agg_download_pkg where period = 'hour') , now() - interval '1 hour') and pkg = ?::text;
END_SQL
    unless ($self->schema->pg) {
        $sql =~ s/::text//g;
        $sql =~ s/interval '(\d+) (day|hour)'/interval $1 $2/g;
    }
    my $res = $self->schema->storage->dbh->selectall_arrayref($sql, {Columns => {}}, $name);
    return $self->render(json => { data => $res });
}

1;
