#!/usr/bin/perl -w

use strict;

my $test = 0;

my $dir = "filesystempath";

chdir($dir) or die "chdir($dir): $!\n";

my(%hash);
my($file);
foreach $file ( <$dir/*> ) {
	my($age) = -M $file;
	next unless ( defined($age) );
	next unless ( $age > 1 );
	my($rc) = 0;
	$rc = unlink($file) unless ( $test );
	print "Removing $file  (age: $age, rc: $rc)\n";
}
