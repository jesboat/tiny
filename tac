#!/usr/bin/env perl
use strict;
use warnings;

my $fh;
my $fname;

if (@ARGV == 0) {
    $fname = "stdin";
    $fh = \*STDIN;
} elsif (@ARGV == 1) {
    $fname = shift;
    open $fh, "<", $fname  or die "$fname: open: $!\n";
} else {
    die "Usage: $0 [infile]\n";
}

my @lines;

while (defined(my $line = <$fh>)) {
    push @lines, \$line;
}
$!  and die "$fname: read $!\n";
close $fh  or die "$fname: close: $!\n";

for (my $i = $#lines; $i >= 0; $i--) {
    print ${$lines[$i]}  or die "write: $!\n";
}

close STDOUT  or die "close: $!\n";

