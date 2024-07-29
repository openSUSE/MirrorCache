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

package MirrorCache::Task::ReportProjectSize;
use Mojo::Base 'Mojolicious::Plugin';


sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(report_project_size => sub { _run($app, @_) });
}

sub _run {
    my ($app, $job, $path) = @_;
    return $job->fail('Empty path is not allowed') unless $path;

    my $minion = $app->minion;
    return $job->finish('Previous report job is still active for ' . $path)
        unless my $guard = $minion->guard('report_project_size_' . $path, 30*60);

    my ($size, $file_cnt, $lm) = $app->schema->resultset('Folder')->calculate_disk_usage($path);

    $job->note("total size" => $size, "file count" => $file_cnt, "last modified" => $lm);

    $app->schema->resultset('Project')->update_disk_usage($path, $size, $file_cnt, $lm);

    return $job->finish;
}

1;
