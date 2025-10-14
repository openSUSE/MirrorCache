# Copyright (C) 2025 SUSE LLC
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

package MirrorCache::Task::Exec;
use diagnostics;
use IPC::Open3;
use IO::Select;
use Symbol 'gensym';
use POSIX ":sys_wait_h";

use Mojo::Base 'Mojolicious::Plugin';
use MirrorCache::Utils 'datetime_now';

# Exec command will execute bash commands provided by argv
#
# Examples to print string "1 2"
# perl:
# my $res = $minion->enqueue(exec => ("echo 1 2"));
# my $res = $minion->enqueue(exec => ("echo", 1, 2));
# my %args = (CMD => 'echo 1', DESC => 'Command that prints "1 2"', TIMEOUT => 1200, LOCK => 'mylock', LOCK_TIMEOUT => 60);
# my $res = $minion->enqueue(exec => (\%args, 1, 2));
#
# shell:
# /usr/share/mirrorcache/script/mirrorcache minion job -e exec -q myqueue -a '["echo 1 2"]'
# /usr/share/mirrorcache/script/mirrorcache minion job -e exec -q myqueue -a '["echo", 1, 2]'
# /usr/share/mirrorcache/script/mirrorcache minion job -e exec -q myqueue -a '[{"CMD":"echo","DESC":"Command that prints","LOCK":"mylock"}, 1, 2]'

sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(exec => sub { _run($app, @_) });
}

sub _run {
    my ($app, $job, $arg0, @argv) = @_;
    my $minion = $app->minion;

    return $job->finish('No command provided') unless $arg0;

    my ($cmd, $cmdline, $desc, $timeout, $lockname, $locktimeout, @args);

    if (ref $arg0 eq "HASH") {
        $cmdline      = $arg0->{CMD};
        $desc         = $arg0->{DESC};
        $timeout      = $arg0->{TIMEOUT};
        $lockname     = $arg0->{LOCK};
        $locktimeout  = $arg0->{LOCK_TIMEOUT};
    } else {
        $cmdline = $arg0;
    }

    my @cmdline = split(/\s/, $cmdline, 2);
    if (scalar(@cmdline) > 1) {
        $cmd  = $cmdline[0];
    } else {
        $cmd = $cmdline;
    }
    $desc        = $desc // "Command $cmd";
    $timeout     = $timeout // 1200;
    $lockname    = $lockname // "EXEC_LOCK_$cmd";
    $locktimeout = $locktimeout // $timeout;

    return $job->finish("Cannot lock $lockname")
        unless my $guard = $minion->guard($lockname, $locktimeout);

    my $pid;
    my ($infh,$outfh,$errfh);
    $errfh = gensym();

    my $success = 0;
    my $error;
    eval {
        $pid = open3($infh, $outfh, $errfh, $cmdline, @argv);
        $success = 1;
    };
    return $job->fail("open3: $@") unless $success;
    close($infh);

    my $sel = new IO::Select;
    $sel->add($outfh, $errfh);

    my $start_time = time;
    $job->note(pid => $pid, start_time => $start_time, cmdline => $cmdline);

    while(1) {
        $! = 0;
        my @ready = $sel->can_read(5);
        my $last = 0;
        if ($!) { # error
            $job->note(error_code => $!);
            print STDERR "ERRR: $!\n";
            waitpid(-1, WNOHANG);
            $last = 1;
        }
        my $curr_time = time;
        my (@lines, @elines);
        foreach my $fh (@ready) {
            my $line = <$fh>;
            if(not defined $line){
                $sel->remove($fh);
                next;
            }
            chomp($line);
            if($fh == $outfh) {
                push @lines, $line;
            } elsif($fh == $errfh) {# do the same for errfh  
                push @elines, $line;
            }
        }
        $job->note("$curr_time O" => @lines)  if @lines;
        $job->note("$curr_time E" => @elines) if @elines;

        my $x = waitpid($pid, WNOHANG);
        if ($x < 0) {
            $job->note(finished => $pid);
            $last = 1;
        }

        last if $last;
        if (($curr_time - $start_time) >= $timeout) {
            waitpid(-1, WNOHANG);
            return $job->fail("timeout expired!");
        }
    }

    waitpid(-1, WNOHANG);
    return $job->finish('finish');
}

1;
