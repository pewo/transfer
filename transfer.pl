#!/usr/bin/perl -wT

use strict;
use Data::Dumper;
my ($debug) = 0;

use lib ".";
use Transfer;

use Getopt::Long;
my $conf = $0 . ".conf";
my $verbose;

GetOptions(
    "conf=s"  => \$conf,
    "verbose" => \$verbose
) or die("Error in command line arguments\n");

print "conf: $conf\n" if ($debug);

my ($transfer) = new Transfer( debug => $debug, conf => $conf );
die "Unable to create Transfer object" unless ($transfer);

print Dumper( \$transfer );

$transfer->transfer();
