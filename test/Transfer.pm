package Object;

use strict;
use Carp;

$Object::VERSION = '0.0.1';

sub set($$$) {
    my ($self)  = shift;
    my ($what)  = shift;
    my ($value) = shift;

    $what =~ tr/a-z/A-Z/;

    $self->{$what} = $value;
    my($val) = "undef";
    $val = $value if ( defined($value) );
    $self->debug( 9, "setting $what to $val" );
    return ($value);
}

sub get($$) {
    my ($self) = shift;
    my ($what) = shift;

    $what =~ tr/a-z/A-Z/;
    my $value = $self->{$what};

    return ( $self->{$what} );
}

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {};

    bless( $self, $class );

    my (%args) = @_;

    my ( $key, $value );
    while ( ( $key, $value ) = each %args ) {
        $key =~ tr/a-z/A-Z/;
        $self->set( $key, $value );
    }

    return ($self);
}

package Transfer;

use strict;
use Carp;
use Data::Dumper;
use File::Copy;
use File::Basename;
use File::Temp;
use Cwd;
use Fcntl qw(:flock);
use Sys::Hostname;
use Scalar::Util qw(openhandle);

my ($debug) = 0;
$Transfer::VERSION = '0.1.0';
@Transfer::ISA     = qw(Object);

####################################
# new(@_)
# Creates a new Transfer object
# Valid parameters are
#   debug => 0-9
#   conf => configuration filename
####################################
sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = {};
    bless( $self, $class );

    my (%default_config) = (
        "ext"         => "asc",
        "sum"         => "sha256sum",
        "maxtransfer" =>  2 * 1000 * 1000 * 1000,
        "splitbytes"  => 512 * 1000 * 1000,
        "sleep"       => 31,
    );

    $self->set( "debug", 0 );


    my (%hash) = (@_);
    if ( defined( $hash{debug} ) ) {
        $debug = $hash{debug};
        $self->set( "debug", $hash{debug} );
    }
    while ( my ( $key, $val ) = each(%hash) ) {
        $self->set( $key, $val );
        $self->debug( 5, "initiating [$key] to [$val]" );
    }
    my ($conf) = $self->get("conf");

    foreach ( keys %default_config ) {
        $self->config( $_, $default_config{$_} );
        $self->debug( 9,
            "setting default config value $_ = $default_config{$_}" );
    }
    croak "new needs parameter 'conf'" unless ( defined($conf) );
    $self->debug( 9, "trying to lock $conf" );
    croak "Unable to get lock on $conf" unless ( $self->lock($conf) );
    $self->debug( 9, "trying to read $conf" );
    croak "Something wrong in $conf" unless ( $self->readconf($conf) );

    $self->set("version",$Transfer::VERSION);

    $self->debug( 9, "returning new object " . Dumper(\$self) );
    return ($self);
}

####################################
# readfile($filename)
# Reads file and return as an array
####################################
sub readfile() {
    my ($self) = shift;
    my ($file) = shift;
    my (@res)  = ();
    if ( open( IN, "<$file" ) ) {
        foreach (<IN>) {
            chomp;
            push( @res, $_ );
        }
        close(IN);
    }
    return (@res);
}

####################################
# readconf($conf)
# Import configuration parameters
####################################
sub readconf() {
    my ($self) = shift;
    my ($conf) = shift;
    my (%res)  = ();

    unless ( defined($conf) ) {
        $self->debug( 0, "readconf need \$conf parameter" );
        return (undef);
    }

    $self->debug( 5, "reading configuration file $conf" );
    my (@content) = $self->readfile($conf);

    foreach (@content) {
        next unless ( defined($_) );
        chomp;
        s/#.*//g;
        s/^\s+//;
        s/\s+$//;
        next if ( $_ =~ /^$/ );
        my ( $key, $value ) = split( /\s*=\s*/, $_ );
        $self->debug( 5, "configuration: key=[$key], value=[$value]" );
        next unless ( defined($key) );
        next unless ( defined($value) );
        $self->config( $key, $value );
    }
    return ( $self->validateconf() );
}

####################################
# checkdir($dir)
# Checks if $dir contains valid charactes
# and is an existing directory
####################################
sub checkdir() {
    my ($self) = shift;
    my ($dir)  = shift;

    unless ( defined($dir) ) {
        return (undef);
    }

    $self->debug( 9, "check if $dir is valid and a directory" );

    unless ( $dir =~ /^[\/\w]+$/ ) {
        $self->debug( 0, "$dir contains bad characters" );
        return (undef);
    }
    if ( !-d $dir ) {
        $self->debug( 0, "$dir is not a directory" );
        return (undef);
    }
    else {
        $self->debug( 9, "$dir is OK" );
        return ($dir);
    }
}

sub config() {
    my ($self)  = shift;
    my ($key)   = shift;
    my ($value) = shift;
    return (undef) unless ( defined($key) );
    if ( defined($value) ) {
        return ( $self->set( "config_" . $key, $value ) );
    }
    else {
        return ( $self->get( "config_" . $key ) );
    }
}

sub validateconf() {
    my ($self) = shift;
    my (%conf) = @_;

    my ($rc);
    my ($src) = $self->config("src");
    $rc = $self->checkdir($src);
    unless ($rc) {
        $self->debug( 0,
            "config is missing src key or value is not a directory" );
        return (undef);
    }
    $self->debug( 5, "checked src($src) directory" );

    my ($dst) = $self->config("dst");
    $rc = $self->checkdir($dst);
    unless ($rc) {
        $self->debug( 0,
            "config is missing dst key or value is not a directory" );
        return (undef);
    }
    $self->debug( 5, "checked dst($dst) directory" );

    my ($ext) = $self->config("ext");
    unless ( defined($ext) ) {
        $self->debug( 0, "config is missing ext key" );
        return (undef);
    }
    $self->debug( 5, "checked ext($ext) key" );

    my ($sum) = $self->config("sum");
    unless ( defined($sum) ) {
        $self->debug( 0, "config is missing sum key" );
        return (undef);
    }
    $self->debug( 5, "checked sum($sum) key" );
    my ($sumbin) = undef;
    if ( $sum =~ /^\w+$/ ) {
        if ( -x "/usr/bin/$sum" ) {
            $sumbin = "/usr/bin/$sum";
        }
        elsif ( -x "/bin/sum" ) {
            $sumbin = "/bin/$sum";
        }
    }

    if ( defined($sumbin) && -x $sumbin ) {
        $self->config( "sumbin", $sumbin );
    }
    else {
        $self->debug( 0, "Missing executable $sum" );
        return (undef);
    }
    $self->debug( 5, "setting sumbin to $sumbin" );

    my ($splitbin) = undef;
    if ( -x "/usr/bin/split" ) {
        $splitbin = "/usr/bin/split";
    }
    elsif ( -x "/bin/split" ) {
        $splitbin = "/bin/split";
    }
    if ( defined($splitbin) && -x $splitbin ) {
        $self->config( "splitbin", $splitbin );
    }
    else {
        $self->debug( 0, "Missing executable split" );
        return (undef);
    }
    $self->debug( 5, "setting splitbin to $splitbin" );

    my ($catbin) = undef;
    if ( -x "/usr/bin/cat" ) {
        $catbin = "/usr/bin/cat";
    }
    elsif ( -x "/bin/cat" ) {
        $catbin = "/bin/cat";
    }

    if ( defined($catbin) && -x $catbin ) {
        #
        # Tainting $catbin
        #
        unless ( $catbin =~ m#^([\/\w.-]+)$# ) {    # $1 is untainted
            die "filename '$catbin' has invalid characters.\n";
        }
        $catbin = $1;
        $self->config( "catbin", $catbin );
    }
    else {
        $self->debug( 0, "Missing executable cat" );
        return (undef);
    }
    $self->debug( 5, "setting catbin to $catbin" );

    my ($maxtransfer) = $self->config("maxtransfer");
    unless ($maxtransfer) {
        $maxtransfer = 2 * 1000 * 1000 * 1000;    # 2 GB
        $self->config( "maxtransfer", $maxtransfer );
        $self->debug( 5, "setting maxtransfer to $maxtransfer" );
    }

    my ($splitbytes) = $self->config("splitbytes");
    unless ($splitbytes) {
        $splitbytes = 512 * 1000 * 1000;          # 512 MB
        $self->config( "splitbytes", $splitbytes );
        $self->debug( 5, "setting splitbytes to $splitbytes" );
    }

    my ($low) = $self->config("low");
    if ( defined($low) ) {
        $self->config( "low", 1 ) if ($low);
        $self->debug( 5, "this is low side" );
    }

    my ($high) = $self->config("high");
    if ( defined($high) ) {
        $self->config( "high", 1 ) if ($high);
        $self->debug( 5, "this is high side" );
    }

    unless ( $self->config("low") or $self->config("high") ) {
        $self->debug( 0, "config is missing low or high key" );
        return (undef);
    }

    return (1);
}

sub checksum() {
    my ($self)   = shift;
    my ($srcext) = shift;
    my (@cmd)    = @_;
    my (@res)    = ();
    delete @ENV{qw(PATH IFS CDPATH ENV BASH_ENV)};
    my ($sumbin) = $self->config("sumbin");

    #
    # Tatinting srcext
    #
    unless ( $srcext =~ m#^([\w.-]+)$# ) {    # $1 is untainted
        die "filename '$srcext' has invalid characters.\n";
    }
    $srcext = $1;

    #
    # Tainting $sumbin
    #
    unless ( $sumbin =~ m#^([\/\w.-]+)$# ) {    # $1 is untainted
        die "filename '$sumbin' has invalid characters.\n";
    }
    $sumbin = $1;

    $self->debug( 5, "executing $sumbin --check --ignore-missing $srcext" );
    open( my $listing, "-|", $sumbin, "--check", "--ignore-missing", $srcext )
      or croak "error executing command: stopped";
    while (<$listing>) {
        next unless ( defined($_) );
        chomp;
        $self->debug( 9, "$srcext: $_" );
	if ( $_ =~ /FAILED/i ) {
		$self->debug(0,"Checksum failed, exiting...");
		exit(1);
	}
        if ( $_ =~ /:\s+OK/ ) {
            $_ =~ s/:\s+OK.*//;
            $self->debug( 9, "adding $_ to valid files" );
            push( @res, $_ );
        }
    }
    close($listing);
    return (@res);
}

sub wait_until_transfered() {
    my ($self) = shift;
    my ($file) = shift;
    return (undef) unless ( defined($file) );
    my ($dst)     = $self->config("dst");
    my ($dstfile) = $dst . "/" . $file;
    unless ( $dstfile =~ m#^([\/\w.-]+)$# ) {    # $1 is untainted
        die "filename '$dstfile' has invalid characters.\n";
    }
    $dstfile = $1;
    my ($start) = time;
    my ($sleep) = $self->config("sleep") || 60;
    my ($i)     = 0;
    while (1) {
        last unless ( -r $dstfile );
        $i += sleep($sleep);
        $self->debug( 0,
                "Waited $i(s) for $dstfile to be transfered. Started:"
              . localtime($start)
              . ", Now: "
              . localtime(time) );
    }
    return ($i);
}

sub mover() {
    my ($self)    = shift;
    my ($file)    = shift;
    my ($nosplit) = shift;
    return (undef) unless ( defined($file) );

    my ($src)     = $self->config("src");
    my ($dst)     = $self->config("dst");
    my ($srcfile) = $src . "/" . $file;
    my ($dstfile) = $dst . "/" . $file;
    unless ( $srcfile =~ m#^([\/\w.-]+)$# ) {    # $1 is untainted
        die "filename '$srcfile' has invalid characters.\n";
    }
    $srcfile = $1;
    unless ( $dstfile =~ m#^([\/\w.-]+)$# ) {    # $1 is untainted
        die "filename '$dstfile' has invalid characters.\n";
    }
    $dstfile = $1;

    $self->debug( 5, "trying to move $srcfile to $dstfile" );

    my (
        $dev,  $ino,   $mode,  $nlink, $uid,     $gid, $rdev,
        $size, $atime, $mtime, $ctime, $blksize, $blocks
    ) = stat($srcfile);
    unless ( defined($size) ) {
        $self->debug( 0, "unable to stat $srcfile: $!" );
        return (undef);
    }
    $self->debug( 5, "$srcfile size is $size" );
    my ($splitbytes) = $self->config("splitbytes");
    $self->debug( 5, "splitbytes is $splitbytes" );

    if ( defined($nosplit) || $size <= $splitbytes ) {
        $self->debug("will not split file");
    }
    else {
        my ($split) = 0;
        $split = $self->splitter($srcfile);
        return ($size) if ($split);
    }

    my ($rc) = 0;
    $rc = move( $srcfile, $dstfile );
    if ($rc) {
        $self->debug( 0, "move($srcfile,$dstfile) OK" );
    }
    else {
        $self->debug( 0, "move($srcfile,$dstfile) error: $!" );
        return (undef);
    }

    return ($size);
}

sub prepare() {
    my ($self)   = shift;
    my ($srcext) = shift;

    $self->debug( 5, "preparing from $srcext" );
    unless ( open( IN, "<", $srcext ) ) {
        $self->debug(0, "Reading $srcext: $!");
        return (undef);
    }
    foreach (<IN>) {
        chomp;
        my ($file) = undef;
        if (m/^\w+\s+(\w+.*)$/) {
            $file = $1;
        }
        next unless ($file);
        $self->debug( 5, "file is $file" );
        if ( -r $file ) {
            $self->debug( 5, "File $file exists, skipping rebuild" );
            next;
        }

	my($firstfile) = $file . ".part.0000";
	if ( ! -r $firstfile ) {
            $self->debug( 5, "File $firstfile is missing, skipping rebuild" );
            next;
	}

        $self->debug( 0, "File $file is missing, trying to rebuild" );
        unlink($file);

        my ($src);
        foreach $src (<$file.part.*>) {
            unless ( $src =~ m#^([\/\w.-]+)$# ) {    # $1 is untainted
                die "filename '$src' has invalid characters.\n";
            }
            $src = $1;
            $self->debug( 9, "adding $src to valid files" );
            my ($catbin) = $self->config("catbin");
            delete @ENV{qw(PATH IFS CDPATH ENV BASH_ENV)};

            my ($rc) = system("$catbin $src >> $file");
            unless ($rc) {
                $self->debug( 0, "Adding $src to $file OK" );
                #unless ( unlink($src) ) {
                #    $self->debug( 0, "Unlinking $src failed: $!" );
                #    return (undef);
                #}
                #else {
                #    $self->debug( 0, "Unlinked $src OK" );
                #}
            }
            else {
                $self->debug( 0, "Adding $src to $file failed: $!" );
                return (undef);
            }
        }

	#
	# We have to check that checksum is OK before removing source files...
	#

    	delete @ENV{qw(PATH IFS CDPATH ENV BASH_ENV)};
    	my ($sumbin) = $self->config("sumbin");

    	#
    	# Tatinting srcext
    	#
    	unless ( $srcext =~ m#^([\w.-]+)$# ) {    # $1 is untainted
        	die "filename '$srcext' has invalid characters.\n";
    	}
    	$srcext = $1;

    	#
    	# Tainting $sumbin
    	#
    	unless ( $sumbin =~ m#^([\/\w.-]+)$# ) {    # $1 is untainted
        	die "filename '$sumbin' has invalid characters.\n";
    	}
        $sumbin = $1;

	$self->debug(5, "executing $sumbin --check --ignore-missing $srcext");
	my($rc) = system("$sumbin --check --ignore-missing $srcext");
	$self->debug(5, "DEBUG rc: $rc");
	if ( $rc != 0 ) {
		$self->debug(5, "checksum failed, removing $file and exiting...");
		unlink($file);
		$self->debug(5, "DEBUG exiting...");
		exit($rc);
	}

	$self->debug(5, "checksum for rebuilded files is OK, removing source files");

	foreach $src (<$file.part.*>) {
            unless ( $src =~ m#^([\/\w.-]+)$# ) {    # $1 is untainted
                die "filename '$src' has invalid characters.\n";
            }
            $src = $1;
            unless ( unlink($src) ) {
                $self->debug( 0, "Unlinking $src failed: $!" );
            }
            else {
                $self->debug( 0, "Unlinked $src OK" );
            }
	}

    }
    close(IN);
    return (1);
}

sub transfer() {
    my ($self)        = shift;
    my ($ext)         = $self->config("ext");
    my ($src)         = $self->config("src");
    my ($dst)         = $self->config("dst");
    my ($sum)         = $self->config("sum");
    my ($maxtransfer) = $self->config("maxtransfer");
    my ($low)         = $self->config("low");
    my ($high)        = undef;
    my ($lastdebug)   = undef;

    my ($sleep) = $self->config("sleep") || 60;

    unless ( $src =~ m#^([\/\w.-]+)$# ) {    # $1 is untainted
        die "filename '$src' has invalid characters.\n";
    }
    $src = $1;
    $self->debug( 5, "src directory is $src" );

    my $cwd = getcwd;
    unless ( $cwd =~ m#^([\/\w.-]+)$# ) {    # $1 is untainted
        die "filename '$cwd' has invalid characters.\n";
    }
    $cwd = $1;
    $self->debug( 5, "cwd is $cwd" );
    $self->config( "cwd", $cwd );
    chdir($cwd) or die "chdir($cwd): $!\n";
    chdir($src) or die "chdir($src): $!\n";

    my ($srcext);
    my ($totsize) = 0;
    my (@srcext)  = ();
    my ($files)   = 0;
    foreach $srcext (<*.$ext>) {
        $files++;
        push( @srcext, $srcext );
        my ($tmpdebug) = $srcext . ".low";
        if ( -r $tmpdebug ) {
            $lastdebug = $srcext . ".high";
            $self->debug( 9, "setting lastdebug to $lastdebug" );
        }
        $self->debug( 5, "adding file $files, $srcext to list of valid files" );
    }

    if ($files) {
        unless ( defined($low) ) {
            $low  = 0;
            $high = 1;
            $self->debug( 0, "starting transfer on high side" );
        }
        else {
            $low  = 1;
            $high = 0;
            $self->debug( 0, "starting transfer on low side" );
        }
    }
    else {
        $self->debug( 1, "nothing to do, exiting..." );
        exit(0);
    }

    my ($lastsrcext)  = undef;
    my ($lastsrcfile) = undef;
    foreach $srcext (@srcext) {
        $lastsrcext = $srcext;
        my ($start) = time;
        $self->debug( 9, "starting time is $start " . localtime(time) );

        $self->debug( 5, "processing $srcext" );
        if ($high) {
            unless ( $self->prepare($srcext) ) {
                $self->debug( 0, "problem when preparing $srcext, skipping" );
                next;
            }
        }
        my (@srcext) = $self->checksum($srcext);
        $self->debug( 9, "chdir($cwd)" );
        chdir($cwd) or die "chdir($cwd): $!\n";
        my ($srcfile);
        my ($sent) = 0;
        $files = 0;
        my (%fileinfo) = ();

        foreach $srcfile (@srcext) {
            $files++;
            $self->debug( 5, "processing file $files, $srcfile" );
            my ($size) = 0;

            $fileinfo{$srcfile} = 0;

            my ($retries) = 3;
            while ( $retries-- ) {
                if ($high) {    # Do not split
                    $size = $self->mover( $srcfile, 1 );
                }
                else {
                    $size = $self->mover($srcfile);
                }
                last if ($size);
                $self->debug( 0,
"retrying($retries) transfer of $srcfile, sleeping $sleep seconds"
                );
                sleep($sleep);
            }
            unless ( defined($size) ) {
                $self->debug( 0, "skipping $srcfile, to many retries" );
                next;
            }

            $totsize += $size;
            $sent    += $size;
            $fileinfo{$srcfile} = $size;

            if ($low) {
                if ( $totsize > $maxtransfer ) {
                    $self->debug(9,"totsize: $totsize, maxtransfer: $maxtransfer");
                    $self->wait_until_transfered($srcfile);
                    $totsize = 0;
                }
                $lastsrcfile = $srcfile;
            }
        }

        if ( $low && $lastsrcfile ) {
            $self->debug( 5, "last srcfile is $lastsrcfile" );
            $self->wait_until_transfered($lastsrcfile);
        }

        my ($end)   = time;
        my ($stats) = $src . "/" . $srcext . ".stats";
        #
        # Tainting $stats
        #
        unless ( $stats =~ m#^([\/\w.-]+)$# ) {    # $1 is untainted
            die "filename '$stats' has invalid characters.\n";
        }
        $stats = $1;
        if ( open( STATS, ">>", $stats ) ) {
            $self->debug( 5, "creating statistics file $stats" );
            my ($dur) = $end - $start;
            my ($i)   = 0;
            my ($pre) = "";
            if ($low) {
                $pre = "low";
            }
            else {
                $pre = "high";
            }
            print STATS $pre . "start=$start\n";
            print STATS $pre . "end=$end\n";
            print STATS $pre . "dur=$dur\n";
            print STATS $pre . "files=$files\n";
            print STATS $pre . "sent=$sent\n";
            print STATS $pre . "srv=" . hostname . "\n";
            print STATS $pre . "ver=$Transfer::VERSION\n";

            foreach ( sort keys %fileinfo ) {
                print STATS $pre . "file"
                  . $i++ . "="
                  . $_
                  . ",$fileinfo{$_}\n";
            }
            close(STATS);
            if ( $high ) {
              my($tmpstats) = "/tmp/transfer.devc3mgr.stats";
              unlink($tmpstats);
              copy($stats, $tmpstats);
            }
            $self->debug( 9, "moving $stats" );
            $self->mover( basename($stats), 1 );
        }

        $self->mover( $srcext, 1 );
        if ($low) {
            $self->wait_until_transfered($srcext);
        }
        chdir($src) or die "chdir($src): $!\n";
        $self->debug( 5, "chdir($src)" );
        $self->debug( 9, "ending time is $end " . localtime($end) );
    }

    if ( $self->get("debug") > 0 || $lastdebug ) {
        my ($debugname) = $self->get("debugname");
        chdir($cwd) or die "chdir($cwd): $!\n";
        $self->debug("cwd: $cwd");
        my ($lowdebugfile)  = $src . "/" . $lastsrcext . ".low";
        my ($highdebugfile) = $src . "/";
        $highdebugfile .= $lastdebug if ($lastdebug);
        my ($debugfile);
        my (@debugfiles) = ();

        #
        # Tainting $lowdebugfile
        #
        unless ( $lowdebugfile =~ m#^([\/\w.-]+)$# ) {    # $1 is untainted
            die "filename '$lowdebugfile' has invalid characters.\n";
        }
        $lowdebugfile = $1;
        #
        # Tainting $highdebugfile
        #
        unless ( $highdebugfile =~ m#^([\/\w.-]+)$# ) {    # $1 is untainted
            die "filename '$highdebugfile' has invalid characters.\n";
        }
        $highdebugfile = $1;

        if ($high) {
            $debugfile = $highdebugfile;
        }
        else {
            $debugfile = $lowdebugfile;
        }

        push( @debugfiles, $lowdebugfile );
        push( @debugfiles, $highdebugfile ) if ($high);

        $self->debug( 9, "debugfile: $debugfile" );
        $self->debug( 9, "debugname: $debugname" );
        if ($debugname) {
            my ($fh) = $self->get("debugfh");
            close($fh);
            copy( $debugname, $debugfile );
            foreach (@debugfiles) {
                $self->mover( basename($_), 1 );
            }
        }
    }
}

sub lock() {
    my ($self) = shift;
    my ($file) = shift;

    unless ( open( LOCK, "<", $file ) ) {
        $self->debug(0, "Reading $file: $!");
        return (undef);
    }
    unless ( flock( LOCK, LOCK_EX | LOCK_NB ) ) {
        $self->debug(0, "Can't get lock on $file");
        return (undef);
    }
    return (1);
}

sub splitter() {
    my ($self)       = shift;
    my ($srcfile)    = shift;
    my ($splitbytes) = $self->config("splitbytes");
    my ($splitbin)   = $self->config("splitbin");
    my ($maxtransfer)= $self->config("maxtransfer");

    my (
        $dev,  $ino,   $mode,  $nlink, $uid,     $gid, $rdev,
        $size, $atime, $mtime, $ctime, $blksize, $blocks
    ) = stat($srcfile);
    unless ( defined($size) ) {
        $self->debug( 0, "unable to stat $srcfile: $!" );
        return (undef);
    }

    if ( $size < $splitbytes ) {
        $self->debug( 5,
            "No need too split $srcfile $size is less then $splitbytes" );
        return (0);
    }

    my ($rc);
    #
    # Tainting $splitbin
    #
    unless ( $splitbin =~ m#^([\/\w.-]+)$# ) {    # $1 is untainted
        die "filename '$splitbin' has invalid characters.\n";
    }
    $splitbin = $1;

    #
    # Tainting $splitbytes
    #
    unless ( $splitbytes =~ m#^(\d+)$# ) {    # $1 is untainted
        die "splitbytes '$splitbytes' has invalid characters.\n";
    }
    $splitbytes = $1;

    open(
        my $listing,          "-|",                $splitbin,
        "--verbose",          "--suffix-length=4", "--bytes=$splitbytes",
        "--numeric-suffixes", "$srcfile",          "$srcfile.part."
    ) or croak "error executing command: stopped";
    while (<$listing>) {
        $self->debug( 9, "split: $_" );
    }
    close($listing);

    my ($splitpath);
    my($totsize) = 0;
    foreach $splitpath (<$srcfile.part.*>) {
        my ($splitfile) = basename($splitpath);
        $totsize += $self->mover( $splitfile, 1 );
        $self->debug( 9, "splitfile: $splitfile, totsize: $totsize, maxtransfer: $maxtransfer" );
        if ( $totsize > $maxtransfer ) {
            $totsize = 0;
            $self->wait_until_transfered($splitfile);
        }
    }
    unlink($srcfile);
    return (1);
}

sub debug() {
    my ($self)  = shift;
    my ($level) = shift;
    my ($msg)   = shift;

    return unless ( defined($level) );
    unless ( $level =~ /^\d$/ ) {
        $msg   = $level;
        $level = 1;
    }
    my ($fh) = $self->get("debugfh");
    unless ($fh) {
        $fh = File::Temp->new();
        $self->set( "debugfh",   $fh );
        $self->set( "debugname", $fh->filename );
    }
    my ($debug) = $self->get("debug");
    my ( $package0, $filename0, $line0, $subroutine0 ) = caller(0);
    my ( $package1, $filename1, $line1, $subroutine1 ) = caller(1);

    chomp($msg);
    my ($str) = "DEBUG($level,$debug,$subroutine1:$line0): $msg";
    if ($fh) {
        if ( openhandle($fh) ) {
            print $fh $str . "\n";
        }
    }

    if ( $level == 0 ) {
        print $msg . "\n";
    }
    elsif ( $debug >= $level ) {
        print $str . "\n";
        return ($str);
    }
    else {
        return (undef);
    }
}
1;

