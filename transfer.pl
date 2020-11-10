#!/usr/bin/perl -wT

use strict;
use Data::Dumper;
my($debug) = 0;

use lib ".";
use Transfer;


use Getopt::Long;
my $conf   = $0 . ".conf";
my $verbose;

GetOptions (
    "conf=s" => \$conf,
    "verbose"  => \$verbose
) or die("Error in command line arguments\n");

print "conf: $conf\n" if ( $debug );

my($transfer) = new Transfer( debug => $debug );
my(%conf) = $transfer->readconf($conf);

my($rc);
$rc = $transfer->validateconf(%conf);
unless ( $rc ) {
  die "Something wrong in $conf\n";
}

$transfer->transfer();
