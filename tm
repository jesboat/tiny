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

__END__

=pod

=head1 NAME

tm - render timestamps in a human-readable format


=head1 SYNOPSIS

    tm 1510588745

    tm 1510588745000 1479052745000

    (echo 1510588745; echo 1479052745) | tm

    tm 1479052745000000000

    tm --paste


=head1 DESCRIPTION

B<tm> reads numeric timestamps and prints them in human-readable format.

Timestamps must be either UNIX time (seconds since the UNIX epoch, of
January 1, 1990; see L<time(3)>), or UNIX time in milliseconds since the
epoch, or UNIX time in nanoseconds since the epoch.

B<tm> can run in three modes.

=over 4

=item *

When run with arguments, B<tm> attempts to render every argument, and prints
the human-readable versions one per line (in the same order that they were
listed in the argument list.) If only a single argument is given, the output
will consist of nothing but the human-readable timestamp; otherwise, output
lines may include a prefix indicating which argument they correspond to.

=item *

When run without arguments, B<tm> reads timestamps from standard input. Each
line on standard input should be a single timestamp. For each input line,
B<tm> will print the corresponding human-readable version alone on a line to
standard output.

=item *

When run with the C<--paste> option, B<tm> will run continuously. It will
monitor the system clipboard, and, when the clipboard appears to contain a
timestamp, it will render the timestamp to standard output.

The intent is that somebody who frequently does timestamp conversions can
simply leave C<tm --paste> running in a terminal; all they need to do to render
a timestamp is copy it, and the human-readable version will be printed by B<tm>
with no further action necessary.

=back


=head1 OPTIONS

=over 2

=item B<--paste>

Instead of printing timestamps from the arguments or standard input, run
continuously, printing any timestamps found on the system clipboard.

=back


=head1 RETURN VALUE

Returns 0 if all timestamps were successfully parsed and rendered.
Returns non-zero otherwise.


=head1 EXAMPLES

Render a single timestamp, given in seconds:

    $ tm 1510588745
    Mon Nov 13 10:59:05 2017
    $

Render multiple timestamps (as arguments), given in milliseconds:

    $ tm 1510588745000 1479052745000
    1510588745000 Mon Nov 13 10:59:05 2017
    1479052745000 Sun Nov 13 10:59:05 2016
    $

Render multiple timestamps (on standard input), given in a mix of seconds and
milliseconds:

    $ (echo 1510588745; echo 1479052745000) | tm
    Mon Nov 13 10:59:05 2017
    Sun Nov 13 10:59:05 2016
    $

Render a single timestamp, given in nanoseconds:

    $ tm 1479052745000000000
    Sun Nov 13 10:59:05 2016
    $

Follow the clipboard. Note that (1) when a timestamp is copied, it is rendered
shortly after; (2) things that don't look like timestamps are silently ignored;
and (3) trailing whitespace is permitted.

    $ tm --paste &
    [1] 2992
    $ echo 1510588745 | pbcopy; sleep 5
    1510588745: Mon Nov 13 10:59:05 2017
    $ echo 'some text including the number 1479052745000' | pbcopy; sleep 5
    $ echo 1510588745000 | pbcopy; sleep 5
    1510588745000: Mon Nov 13 10:59:05 2017
    $ (echo 1510588745000000000; echo; echo) | pbcopy; sleep 5
    1510588745000000000: Mon Nov 13 10:59:05 2017
    $


=head1 CAVEATS

B<tm> uses some huerestics to determine whether a timestamp is in seconds,
milliseconds, or nanoseconds. Those huerestics work for timestamps between 1971
and 2039 (inclusive). Using timestamps outside that range will result in an
error.

When run in B<--paste> mode, B<tm> may need to poll the system clipboard. There is
a small delay between polls. This ensures that B<tm> uses negligible CPU.  It
also means that there may be a delay of a couple seconds between when a
timestamp is copied and when B<tm> renders it, and that if multiple timestamps
are copied in rapid succession, B<tm> may miss some.


=head1 AUTHOR

Jonathan Sailor.


=head1 COPYRIGHT AND LICENSE

Copyright 2015-2017, Facebook.
Copyright 2015-2017, Jonathan Sailor.

This script is free software; you may redistribute it and/or modify it
under the terms of the Perl Artistic License.


=cut

