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
use File::Copy;
use Cwd;


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
        delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};
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

sub checkdir() {
  my($self) = shift;
  my($dir) = shift;
  unless ( defined($dir) ) {
    return(undef);
  }
  unless ( $dir =~ /^[\/\w]+$/ ) {
    print "$dir contains bad characters\n";
    return(undef);
  }
  if ( ! -d $dir ) {
    print "$dir is not a directory\n";
    return(undef);
  }
  else {
    return($dir);
  }
}

sub config() {
  my($self) = shift;
  my($key) = shift;
  my($value) = shift;
  return(undef) unless ( defined($key) );
  if ( defined($value) ) {
    return($self->set("config_" . $key,$value));
  }
  else {
    return($self->get("config_" . $key));
  }
}

sub validateconf() {
  my($self) = shift;
  my(%conf) = @_;

  my($rc);
  my($src) = $conf{src};
  $rc = $self->checkdir($src);
  unless ( $rc ) {
    return(undef);
  }
  $self->config("src",$src);
  my($dst) = $conf{dst};
  $rc = $self->checkdir($dst);
  unless ( $rc ) {
    return(undef);
  }
  $self->config("dst",$dst);

  my($ext) = $conf{ext};
  unless ( defined($ext) ) {
    print "Missing ext in config\n";
    return(undef);
  }
  $self->config("ext",$ext);

  my($sum) = $conf{sum};
  unless ( defined($sum) ) {
    print "Missing sum in config\n";
    return(undef);
  }
  my($bin) = undef;
  if ( $sum =~ /^\w+$/ ) {
    if ( -x "/usr/bin/$sum" ) {
        $bin = "/usr/bin/$sum" 
    }
    elsif ( -x "/bin/sum" ) {
      $bin = "/bin/$sum";
    }
  }
       
  if ( defined($bin) && -x $bin ) {
    $self->config("sum",$bin);
  }
  else {
    print "Missing executable $sum\n";
    return(undef);
  }

  return(1);
}

sub checksum() {
  my($self) = shift;
  my($srcext) = shift;
  my(@cmd) = @_;
  my(@res) = ();
  delete @ENV{qw(PATH IFS CDPATH ENV BASH_ENV)};
  my($sum) = $self->config("sum");

  #
  # Tatinting srcext
  #
  unless ($srcext =~ m#^([\w.-]+)$#) {                  # $1 is untainted
      die "filename '$srcext' has invalid characters.\n";
  }
  $srcext = $1; 

  #
  # Tainting $sum
  #
  unless ($sum =~ m#^([\/\w.-]+)$#) {                  # $1 is untainted
    die "filename '$sum' has invalid characters.\n";
  }
  $sum = $1;

  open( my $listing, "-|", $sum,"--check","--ignore-missing",$srcext) or croak "error executing command: stopped";
  while (<$listing>) {
    next unless ( defined($_) );
    chomp;
    if ( $_ =~ /:\s+OK/ ) {
      $_ =~ s/:\s+OK.*//;
      push(@res,$_);
    }
  }
  close($listing);
  return(@res);
}

sub mover() {
  my($self) = shift;
  my($file) = shift;
  return(undef) unless ( defined($file) );

  my($src) = $self->config("src");
  my($dst) = $self->config("dst");
  my($srcfile) = $src . "/" . $file;
  my($dstfile) = $dst . "/" . $file;
  unless ($srcfile =~ m#^([\/\w.-]+)$#) {                  # $1 is untainted
      die "filename '$srcfile' has invalid characters.\n";
  }
  $srcfile = $1;
  unless ($dstfile =~ m#^([\/\w.-]+)$#) {                  # $1 is untainted
      die "filename '$dstfile' has invalid characters.\n";
  }
  $dstfile = $1;

  my($rc) = 0;
  $rc =  move($srcfile, $dstfile);
  print "move($srcfile,$dstfile) = $rc";
  unless ( $rc ) {
    print " (error: $!)";
  }
  print "\n";
}

sub transfer() {
  my($self) = shift;
  my($ext) = $self->config("ext");
  my($src) = $self->config("src");
  my($dst) = $self->config("dst");
  my($sum) = $self->config("sum");

  unless ($src =~ m#^([\/\w.-]+)$#) {                  # $1 is untainted
      die "filename '$src' has invalid characters.\n";
  }
  $src = $1; 

  my $cwd = getcwd;
  unless ($cwd =~ m#^([\/\w.-]+)$#) {                  # $1 is untainted
      die "filename '$cwd' has invalid characters.\n";
  }
  $cwd = $1;
  $self->config("cwd",$cwd);
  chdir($cwd) or die "chdir($cwd): $!\n";
  chdir($src) or die "chdir($src): $!\n";

  my($srcext);
  foreach $srcext ( <*.$ext> ) {
    print "srcext: $srcext\n";
    my(@srcext) = $self->checksum($srcext);
    chdir($cwd) or die "chdir($cwd): $!\n";
    foreach ( @srcext ) {
      $self->mover($_);
    }
    $self->mover($srcext);
    chdir($src) or die "chdir($src): $!\n";
  }
}
1;

