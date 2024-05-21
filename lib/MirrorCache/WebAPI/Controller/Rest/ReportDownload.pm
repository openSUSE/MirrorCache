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
# with this program; if not, see <http://www.gnu.org/licenses/>.

package MirrorCache::WebAPI::Controller::Rest::ReportDownload;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON qw(to_json);

sub list {
    my ($self) = @_;
    my $group  = $self->param('group')  // 'project';
    my $period = $self->param('period') // 'hour';
    my $limit  = 10;

    if ($period eq 'day') {
        ;
    } elsif ($period eq 'hour') {
        ;
    } else {
        return $self->render(status => 422, json => {error => "Unsupported value for period: $period (Expected: 'day' or 'hour')"});
    }

    my $tmp        = '';
    my $key        = '';
    my $sql_select = 'select dt';
    my $sql_agg    = ', sum(cnt_known) as known_files_requested, sum(case when mirror_id > 0 then cnt_known else 0 end) as known_files_redirected,  sum(case when mirror_id = -1 then cnt else 0 end) as known_files_no_mirrors,  sum(cnt) total_requests, sum(case when mirror_id > 0 then bytes else 0 end) as bytes_redirected, sum(case when mirror_id = -1 then bytes else 0 end) as bytes_served, sum(bytes) bytes_total';
    my $sql_from   = ' from agg_download';
    my $sql_where  = " where period = '$period' and dt > now() - interval '$limit $period'";
    $sql_where  = " where period = '$period' and dt > now() - interval $limit $period" unless $self->schema->pg;

    my @params;
    for my $p (qw(country type os arch mirror project)) {
        if (my $v = $self->param($p)) {
            if ($p eq 'mirror') {
                $sql_where  = "$sql_where and agg_download.mirror_id in (select id from server where hostname like ?)";
                push @params, "%$v%";
            } elsif ($p eq 'type') {
                $sql_where  = "$sql_where and agg_download.file_type in (select id from popular_file_type where name like ?)";
                push @params, "%$v%";
            } elsif ($p eq 'os') {
                $sql_where  = "$sql_where and agg_download.os_id in (select id from popular_os where name like ?)";
                push @params, "%$v%";
            } elsif ($p eq 'os_version') {
                $sql_where  = "$sql_where and agg_download.os_id in (select id from popular_os where version like ?)";
                push @params, "%$v%";
            } elsif ($p eq 'arch') {
                $sql_where  = "$sql_where and agg_download.arch_id in (select id from popular_arch where name like ?)";
                push @params, "%$v%";
            } elsif ($p eq 'project') {
                $sql_where  = "$sql_where and agg_download.project_id in (select id from project where name like ?)";
                push @params, "%$v%";
            } else {
                $sql_where  = "$sql_where and agg_download.$p like ?";
                push @params, $v;
            }
        }
    }

    my $sql_group  = ' group by dt';
    my $sql_order  = ' order by dt desc';
    my $sql_limit  = " limit 100000";

    for my $p (split ',', $group) {
        if ($p eq 'project') {
            $tmp       = $tmp . ', p.name as project';
            $key       = $key . ', p.name';
            $sql_from  = $sql_from  . " left join project p on p.id = project_id";
            next;
        }
        if ($p eq 'country') {
            $tmp = $tmp . ', agg_download.country';
            $key       = $key . ", agg_download.country";
            next;
        }
        if ($p eq 'os') {
            $tmp       = $tmp . ', os.name as os';
            $key       = $key . ", os.name";
            $sql_from  = $sql_from  . " left join popular_os os on os_id = os.id";
            next;
        }
        if ($p eq 'os_version') {
            $tmp       = $tmp . ', os.name as os, agg_download.os_version as os_version';
            $key       = $key . ", os.name, agg_download.os_version";
            $sql_from  = $sql_from  . " left join popular_os os on os_id = os.id";
            next;
        }
        if ($p eq 'arch') {
            $tmp       = $tmp . ', arch.name as arch';
            $key       = $key . ", arch.name";
            $sql_from  = $sql_from  . " left join popular_arch arch on arch_id = arch.id";
            next;
        }
        if ($p eq 'mirror') {
            $tmp       = $tmp . ', s.hostname as mirror';
            $key       = $key . ", s.hostname";
            $sql_from  = $sql_from  . " left join server s on mirror_id = s.id";
            next;
        }
        if ($p eq 'type') {
            $tmp       = $tmp . ', ft.name as type';
            $key       = $key . ", ft.name";
            $sql_from  = $sql_from  . " left join popular_file_type ft on file_type = ft.id";
            next;
        }
        next if ($p =~ /^\s*$/);
        return $self->render(status => 422, json => {error => "Unsupported value for group: $p (Valid value is comma separated combination of: project, country, os or os_version, arch, mirror, type)"});
    }
    my $sql = $sql_select . $tmp . $sql_agg . ", concat_ws('', dt $key) as k" . $sql_from . $sql_where . $sql_group . $key . $sql_order . $key . $sql_limit;

    my $schema = $self->schema;
    unless ($schema->pg) {
        $sql =~ s/date_trunc\('hour', dt\)/(date(dt) + interval hour(dt) hour)/g;
        $sql =~ s/date_trunc\('day', dt\)/date(dt)/g;
    }
    my @res;
    eval {
        my $data = $schema->storage->dbh->selectall_hashref($sql, 'k', {}, @params);
        my @keys = sort keys %$data;
        my @data;
        for my $k (@keys) {
            push @data, $data->{$k};
        }
        my %res = (
            data => \@data,
        );
        $self->render( json => \%res );
        1;
    };
    my $error = $@;
    if ($error) {
         print STDERR "RESDOWNLOADREPORT : " . $error . "\n";
         return $self->render(json => {error => $error}, status => 500);
    }
}

1;
