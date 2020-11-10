package Object;


use strict;
use Carp;
use vars qw($VERSION);

$VERSION = '0.01';

sub set($$$) {
        my($self) = shift;
        my($what) = shift;
        my($value) = shift;

        $what =~ tr/a-z/A-Z/;

        $self->{ $what }=$value;
        return($value);
}

sub get($$) {
        my($self) = shift;
        my($what) = shift;

        $what =~ tr/a-z/A-Z/;
        my $value = $self->{ $what };

        return($self->{ $what });
}

sub new {
        my $proto  = shift;
        my $class  = ref($proto) || $proto;
        my $self   = {};

        bless($self,$class);

        my(%args) = @_;

        my($key,$value);
        while( ($key, $value) = each %args ) {
                $key =~ tr/a-z/A-Z/;
                $self->set($key,$value);
        }

        return($self);
}

package Transfer;

use strict;
use Carp;
use Data::Dumper;
use File::Basename;
use File::Copy;

my($debug) = 0;
$Transfer::VERSION = '0.01';
@Transfer::ISA = qw(Object);

sub new {
        my $proto = shift;
        my $class = ref($proto) || $proto;
        my $self  = {};
        bless($self,$class);

        my(%hash) = ( @_ );
        while ( my($key,$val) = each(%hash) ) {
                $self->set($key,$val);
                if ( $key =~ /debug/i ) {
                   $debug = $val;
                }
        }
        return($self);
}

sub trim() {
	my($self) = shift;
	my($key) = shift;
	return(undef) unless ( defined($key) );
	$key =~ s/^\s+//;
	$key =~ s/\s+$//;
	return($key);
}

sub readfile() {
	my($self) = shift;
	my($file) = shift;
	my(@res) = ();
	if ( open(IN,"<$file") ) {
		foreach ( <IN> ) {
			chomp;
			push(@res,$_);
		}
		close(IN);
	}
	return(@res);
}

sub readconf() {
  my($self) = shift;
  my($conf) = shift;
  my(%res) = ();

  unless ( defined($conf) ) {
    print "readconf need \$conf parameter\n";
    return(undef);
  }

  my(@content) = $self->readfile($conf);

  foreach ( @content ) {
    next unless ( defined($_) );
    chomp;
    s/#.*//g;
    s/^\s+//;
    s/\s+$//;
    next if ( $_ =~  /^$/ );
    my($key, $value) = split(/\s*=\s*/,$_);
    print "key: $key\n" if ( $debug );
    print "value: $value\n" if ( $debug );
    next unless ( defined($key) );
    next unless ( defined($value) );
    $res{$key}=$value;
  }

  return(%res);
       
}

1;

