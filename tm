#!/usr/bin/perl
use strict;
use warnings;

use 5.010;


sub t
##   my ($err, $result) = t(12345);
#
# If a timestamp we know how to handle, return $err=0 and $result
# a string which is a human-readable version of the timestamp. Otherwise
# return $err=1 and $result a description of why the timestamp is invalid.
{
    my ($time) = @_;
    my $unit;
    if ($time !~ /^\d+\s*$/) {
        return (1, "Time not numeric");
    } elsif (22222222 < $time and $time < 22222222 * 100) {
        # Seconds between Sep 1970 or June 2040
        # Millis in 1970
        # Nanos in 1970
        $unit = 1;  # seconds
    } elsif (22222222 * 1000 < $time and $time < 22222222 * 1000 * 100) {
        # Seconds between 2674 and 72939
        # Millis between Sep 1970 or June 2040
        # Nanos in 1979
        $unit = 1000;  # millis
    } elsif (22222222 * 1000**3 < $time and $time < 22222222 * 1000**3 * 100) {
        # Seconds in the far future
        # Millis in the far future
        # Nanos between Sep 1970 and June 2040
        $unit = 1000 ** 3;  # nanos
    } else {
        return (1, "only seconds/millis/nanos between 1971 and 2040 are supported");
    }
    my $timestr = localtime($time / $unit);
    return (0, $timestr);
}

sub convert_args
##  my $was_err = convert_args();
#
# Iterate over @ARGV, converting each timestamp and printing the results.
# Returns whether any timestamp had an error.
{
    my $was_err;
    for my $time (@ARGV) {
        my ($err, $timestr) = t($time);
        $was_err ||= $err;
        if (@ARGV > 1) {
            print $time, " ", $timestr, "\n";
        } else {
            print $timestr, "\n";
        }
    }
    return $was_err;
}

sub convert_stdin
##  my $was_err = convert_stdin();
#
# Read and convert timestamps from stdin. Returns whether any timestamp
# had an error.
{
    my $was_err;
    while (<STDIN>) {
    	my ($err, $timestr) = t($_);
    	$was_err ||= $err;
    	print $timestr, "\n";
    }
    return $was_err;
}

sub read_clipboard
##  my $content = read_clipboard();
#
# Reads the first 30 bytes of clipboard from the OS. Returns undef on error.
{
    # Determine a command which can read the clipboard.
    state $clipboard_command;
    if (!defined $clipboard_command) {
        if (`command -v pbpaste`) {
            # OSX
            $clipboard_command = "pbpaste";
        } elsif (`command -v xsel`) {
            # Unix
            $clipboard_command = "xsel -o";
        } else {
            die "$0: unsupported operating system for using --paste\n";
        }
    }

    # Don't reap the fork automatically.
    local $SIG{CHLD} = sub { 1 };

    # Fork+exec it
    my $pid = open my($fh), "-|", $clipboard_command;
    if (! $pid) {
        warn "$0: couldn't run '$clipboard_command': $!\n";
        return undef;
    }

    # Read at most 30 bytes.
    local $/ = \30;  # record size = 30
    my $content = <$fh>; # read first record
    if (!defined $content) {
    	if ($!) {
            warn "$0: read from '$clipboard_command': $!\n";
            return undef;
        } else {
            # clipboard was empty; <$fh> gave us undef because eof
            $content = "";
        }
    }

    # Kill the command if it's still running (e.g. because the clipboard
    # was bigger.) Necessary because otherwise `close($fh)` will wait(2)
    # for it to exit. (This is a quirk of perl's close function.)
    kill PIPE => $pid; # What it would see if we could actually close the pipe
    my $pid2 = wait;
    $pid == $pid2 or die;
    my $exitCode = $?;

    # Make sure that either it was successful or the reason it failed
    # was because we killed it.
    require POSIX;  # load lazily
    if (POSIX::WIFEXITED($exitCode)) {
        if (my $status = POSIX::WEXITSTATUS($exitCode)) {
            warn "$0: command '$clipboard_command' failed with status $status\n";
            return undef;
        }
    } elsif (POSIX::WIFSIGNALED($exitCode)) {
    	my $termsig = POSIX::WTERMSIG($exitCode);
    	if ($termsig != POSIX::SIGPIPE()) {
    	    warn "$0: command '$clipboard_command' failed: signal $termsig\n";
    	    return undef;
        }
    } else {
        die "$0: got wait code $exitCode, wtf";
    }
    
    # Done.
    close $fh;
    return $content;
}

sub convert_paste
##  my $was_err = convert_paste();
#
# Iteratively convert timestamps from the system's clipboard. Returns
# whether any timestamps had an error. If unable to read the system's
# clipboard, dies.
{
    my $previous = "";
    while (1) {
    	my $content = read_clipboard();
    	if (defined $content
    	    and $content ne $previous
    	    and $content =~ /^(\d{8,21})\s*$/)
    	{
    	    my $time = $1;
    	    my ($err, $timestr) = t($time);
    	    print "$time: $timestr\n"; # even if error
            $previous = $content;
        }
        sleep 5;
    }
}

sub usage
##  usage();
#
# Prints usage message and dies.
{
    print STDERR <<EOF
Illegal usage.

To convert single timestamps, specify them as arguments:
    $0 TIMESTAMP [TIMESTAMP2 ...]

To convert timestamps in bulk, pass them on stdin:
    $0 < TIMESTAMPFILE
    $0     # enter at tty

To loop, converting timestamps found in the system's clipboard:
    $0 --paste
EOF
        ;
    exit 1;
}

sub main {
    if (@ARGV) {
    	if ($ARGV[0] eq '--paste') {
    	    convert_paste();
    	    die; # notreached
    	} else {
            usage() if grep { !/^\d+$/ } @ARGV;
    	    my $was_err = convert_args();
    	    return ($was_err ? 1 : 0);
        }
    } else {
    	my $was_err = convert_stdin();
    	return ($was_err ? 1 : 0);
    }
}

exit(main()) unless caller;
