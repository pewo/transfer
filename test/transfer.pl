#!/usr/bin/perl -wT

use strict;
use Data::Dumper;
my ($debug) = 0;

use lib ".";
use Transfer;

use Getopt::Long;
my $conf = $0 . ".conf";
my $verbose;
my $help = undef;

GetOptions(
    "conf=s"  => \$conf,
    "debug=i" => \$debug,
    "verbose" => \$verbose,
    "help" => \$help,
) or die("Error in command line arguments\n");

if ( $help ) {
    print "Usage: $0 --conf=<config> --verbose --help\n";
    exit(0);
}
print "conf: $conf\n" if ($debug);

new Transfer( debug => $debug, conf => $conf )->transfer();
