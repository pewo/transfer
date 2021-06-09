#
# Version 0.0.1
# Date: Wed Jun  9 16:40:02 CEST 2021
#
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

my ($diodwait) = 1;

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
        "sleep"       => 1,
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
        $sumbin = $self->taintfilename($sumbin);
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
        $splitbin = $self->taintfilename($splitbin);
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
        $catbin = $self->taintfilename($catbin);
        $self->config( "catbin", $catbin );
    }
    else {
        $self->debug( 0, "Missing executable cat" );
        return (undef);
    }
    $self->debug( 5, "setting catbin to $catbin" );

    my ($tarbin) = undef;
    if ( -x "/usr/bin/tar" ) {
        $tarbin = "/usr/bin/tar";
    }
    elsif ( -x "/bin/tar" ) {
        $tarbin = "/bin/tar";
    }

    if ( defined($tarbin) && -x $tarbin ) {
        $tarbin = $self->taintfilename($tarbin);
        $self->config( "tarbin", $tarbin );
    }
    else {
        $self->debug( 0, "Missing executable tar" );
        return (undef);
    }
    $self->debug( 5, "setting tarbin to $tarbin" );

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

sub create_checksum() {
    my ($self)   = shift;

    delete @ENV{qw(PATH IFS CDPATH ENV BASH_ENV)};
    my ($sumbin) = $self->config("sumbin");

    my($srcfile);
    my(@res);
    foreach $srcfile ( @_ ) {

        $srcfile = $self->taintfilename($srcfile);
        $self->debug( 5, "executing $sumbin $srcfile" );
        open( my $listing, "-|", $sumbin, $srcfile )
          or croak "error executing command: stopped";
        while (<$listing>) {
            next unless ( defined($_) );
            chomp;
            $self->debug( 9, "$srcfile $_" );
            push(@res,$_);
        }
        close($listing);
    }
    return(@res);
}

sub check_checksum() {
    my ($self)   = shift;
    my ($srcext) = shift;
    my (@cmd)    = @_;
    my (@res)    = ();
    delete @ENV{qw(PATH IFS CDPATH ENV BASH_ENV)};
    my ($sumbin) = $self->config("sumbin");

    $srcext = $self->taintfilename($srcext);

    my($found_error) = 0;

    $self->debug( 5, "executing $sumbin --check $srcext" );
    open( my $listing, "-|", $sumbin, "--check", $srcext )
      or croak "error executing command: stopped";
    while (<$listing>) {
        next unless ( defined($_) );
        chomp;
        if ( $_ =~ /:\s+OK/ ) {
           $self->debug( 9, "$srcext: $_ (this is OK)" );
           $_ =~ s/:\s+OK.*//;
           $self->debug( 9, "adding $_ to valid files" );
           push( @res, $_ );
        }
        else {
           $self->debug( 9, "$srcext: $_ (this is an ERROR)" );
           $found_error = 1;
           @res = ();
        }
    }
    close($listing);
    if ( $found_error ) {
        $self->debug( 1, "Some checksum error, skipping this for now" );
        return();
    }
    # else        
    return (@res);
}

sub wait_until_transfered() {
    my ($self) = shift;
    my ($file) = shift;
    return (undef) unless ( defined($file) );
    my ($dst)     = $self->config("dst");
    my ($dstfile) = $dst . "/" . $file;
    $dstfile = $self->taintfilename($dstfile);
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
    return (undef) unless ( defined($file) );

    my ($src)     = $self->config("src");
    my ($dst)     = $self->config("dst");
    my ($srcfile) = $self->taintfilename($src . "/" . $file);
    my ($dstfile) = $self->taintfilename($dst . "/" . $file);

    $self->debug( 5, "trying to move $srcfile to $dstfile" );

    my (
        $dev,  $ino,   $mode,  $nlink, $uid,     $gid, $rdev,
        $size, $atime, $mtime, $ctime, $blksize, $blocks
    ) = stat($srcfile);
    unless ( defined($size) ) {
        $self->debug( 0, "unable to stat $srcfile: $!" );
        return (undef);
    }

    my ($rc) = 0;
    $rc = move( $srcfile, $dstfile );
    if ($rc) {
        $self->debug( 1, "move($srcfile,$dstfile) OK" );
    }
    else {
        $self->debug( 1, "move($srcfile,$dstfile) error: $!" );
        return (undef);
    }

    return ($size);
}

sub xxxrebuild() {
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

        $self->debug( 0, "File $file is missing, trying to rebuild" );
        unlink($file);


    }
    close(IN);
    return (1);
}

sub taintfilename() {
    my($self) = shift;
    my($file) = shift;
    unless ( $file =~ m#^([\/\w.-]+)$# ) {    # $1 is untainted
            die "filename '$file' has invalid characters.\n";
    }
    $file = $1;
    return($file);
}

sub popen() {
    my($self) = shift;
    my($cmd) = shift;
    my(@res) = ();
    unless ( open(POPEN,"$cmd |") ) {
        die "$cmd: $!\n";
    }
    foreach ( <POPEN> ) {
        chomp;
        push(@res,$_);
    }
    close(POPEN);
    return(@res);
}


sub transfer() {
    my ($self)        = shift;
    my ($ext)         = $self->config("ext");
    my ($src)         = $self->taintfilename($self->config("src"));
    my ($dst)         = $self->taintfilename($self->config("dst"));
    my ($sum)         = $self->config("sum");
    my ($maxtransfer) = $self->config("maxtransfer");
    my ($low)         = $self->config("low");
    my ($tarbin)      = $self->config("tarbin");
    my ($high)        = undef;
    my ($lastdebug)   = undef;

    my ($sleep) = $self->config("sleep") || 60;

    $self->debug( 5, "src directory is $src" );

    my $cwd = $self->taintfilename(getcwd);
    $self->debug( 5, "cwd is $cwd" );
    $self->config( "cwd", $cwd );
    chdir($cwd) or die "chdir($cwd): $!\n";
    chdir($src) or die "chdir($src): $!\n";

     #     0    1    2     3     4    5     6     7     8
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time);
    my $timestamp = sprintf("%04.4d%02.2d%02.2d_%02.2d%02.2d%02.2d",$year+1900,$mon+1,$mday,$hour,$min,$sec);

    my ($start) = time;

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
        $self->debug( 0, "nothing to do, exiting..." );
        exit(0);
    }


    ########
    # high #
    ########
    if ( $high ) {

        my ($catbin) = $self->config("catbin");
        delete @ENV{qw(PATH IFS CDPATH ENV BASH_ENV)};

        #
        # Rebuild tarfile
        #
        foreach $srcext ( @srcext ) {
            my($files) = 0;

            chdir($cwd) or die "chdir($cwd): $!\n";
            chdir($src) or die "chdir($src): $!\n";
            $srcext = $self->taintfilename($srcext);
            $self->debug( 9, "srcext is $srcext");

            #
            # Rebuild tarfile
            #
            my($tarfile) = $srcext;
            $tarfile =~ s/\.tar.*/.tar/;
            my($basefile) = $tarfile;
            $basefile =~ s/\.tar//;
            $self->debug( 9, "tarfile is $tarfile");
            unlink($tarfile);
            $self->debug( 9, "removing $tarfile");

            #
            # create stats and debugfiles
            #
            my($statsfile) = $self->taintfilename($basefile . ".stats");
            my($debugfile) = $self->taintfilename($basefile . ".debug");

            # 
            # get all files in this bundle and rebuild tarfile
            #
            my(@srcfiles) = $self->check_checksum($srcext);
            my($srcfile);
            foreach $srcfile ( @srcfiles ) {
                $srcfile = $self->taintfilename($srcfile);
                $self->debug( 9, "srcfile is $srcfile");

                my ($rc) = system("$catbin $srcfile >> $tarfile");
                if ( $rc ) {
                    $self->debug( 1, "Adding $srcfile to $tarfile failed: $!" );
                }
                else {
                    $self->debug( 1, "Adding $srcfile to $tarfile OK" );
                }
                $self->debug( 5, "Removing $srcfile" );
                unlink($srcfile);
            }

            #
            # check and tarfile
            #
            my($tarcmd) = "$tarbin -tf $tarfile";
            $self->debug( 5, "Testing tarfile $tarcmd");
            my($tarrc) = system($tarcmd);
            $self->debug( 9, "tarrc: $tarrc");
            
            # 
            # Change to cwd to get remote dest correct
            #
            chdir($cwd) or die "chdir($cwd): $!\n";

            # 
            # upload debug and statsfiles
            #

            my($rc) = 0;

            my($statssrc) = $self->taintfilename($src . "/" . $statsfile);
            my($statsdest) = $self->taintfilename($dst . "/" . $statsfile);
            $rc = move($statssrc,$statsdest);
            $self->debug( 9, "move $statssrc to $statsdest, rc=$rc");

            my($debugsrc) = $self->taintfilename($src . "/" . $debugfile);
            my($debugdest) = $self->taintfilename($dst . "/" . $debugfile);
            $rc = move($debugsrc,$debugdest);
            $self->debug( 9, "move $debugsrc to $debugdest, rc=$rc");

            #
            # 
            # unpacking tarfile
            #
            $tarcmd = "$tarbin -C $dst -xvf $src/$tarfile";
            $self->debug( 5, "Unpacking tarfile $tarcmd");
            foreach ( $self->popen($tarcmd) ) {
                $self->debug( 5, "tar: $_");
            }

	    # Remove tarfile
            $rc = unlink("$src/$tarfile");
            $self->debug( 5, "unlinking $src/$tarfile, rc=$rc");

            #
            # Remove asc file
            $rc = unlink("$src/$srcext");
            $self->debug( 5, "unlinking $src/$srcext, rc=$rc");
        
            #
            # create and send som stats
            #
            my($stats) = "";
            my ($end)   = time;
            my ($dur) = $end - $start;
            #my ($i)   = 0;
            my ($pre) = "";
            if ($low) {
                $pre = "low";
            }
            else {
                $pre = "high";
            }
            $stats .= $pre . "start=$start\n";
            $stats .= $pre . "end=$end\n";
            $stats .= $pre . "dur=$dur\n";
            $stats .= $pre . "files=$files\n";
            #$stats .= $pre . "sent=$sent\n";
            $stats .= $pre . "srv=" . hostname . "\n";
            $stats .= $pre . "ver=$Transfer::VERSION\n";
            if ( open(STATS,">>",$statsdest) ) {
                print STATS $stats;
                close(STATS);
            }
            
            #
            # send debug log
            #
            $debugsrc = $self->taintfilename($self->get("debugname"));
            $self->debug(9,"adding debuglog($debugsrc) to $debugdest");
            $self->debug(9,"Exiting high side");
            my($debugfh) = $self->get("debugfh");
            close($debugfh);
            if ( open(IN,"<",$debugsrc) ) {
                if ( open(OUT,">>",$debugdest) ) {
                    print OUT "\n\n\n";
                    foreach ( <IN> ) {
                        print OUT $_;
                    }
                }
                close(IN);
                close(OUT);
            }
        }
    }
    #######
    # low #
    #######
    elsif ( $low ) {
        my ($lastsrcext)  = undef;
        my ($lastsrcfile) = undef;

        my($tarfile) = sprintf("tar.%s.tar",$timestamp);
        $self->debug( 9, "tarfile is $tarfile");
	unlink($tarfile);
        my($ascfile) = sprintf("%s.asc",$tarfile);
        $self->debug( 9, "ascfile is $ascfile");
        my($debugfile) = $self->taintfilename(sprintf("%s/tar.%s.debug",$dst,$timestamp));
        $self->debug( 9, "debugfile is $debugfile");
        my($statsfile) = $self->taintfilename(sprintf("%s/tar.%s.stats",$dst,$timestamp));
        $self->debug( 9, "statsfile is $statsfile");

        my ($sent) = 0;
        $files = 0;
        my (%fileinfo) = ();
	
        #
        # Add all files to the tarfile
        #
        foreach $srcext (@srcext) {
    
            $lastsrcext = $srcext;
            my ($start) = time;
            $self->debug( 9, "starting time is $start " . localtime(time) );
    
            my (@srcext) = $self->check_checksum($srcext);
            my ($srcfile);
    
            foreach $srcfile (@srcext,$srcext) {
                $files++;
                $self->debug( 5, "processing file $files, $srcfile" );
                $srcfile = $self->taintfilename($srcfile);
                $fileinfo{$files}=$srcfile;

                my (
                    $dev,  $ino,   $mode,  $nlink, $uid,     $gid, $rdev,
                    $size, $atime, $mtime, $ctime, $blksize, $blocks
                ) = stat($srcfile);
                $sent += $size;
                
		my($tarcmd) = "$tarbin --remove-files -rvf $tarfile $srcfile";
                $self->debug( 5, "$tarcmd" );
                foreach ( $self->popen($tarcmd) ) {
                    $self->debug( 5, "tarcmd: $_" );
                }
            }
        }
    
        # 
        # split tarfile into smaller chunks
        #
        my ($splitbytes) = $self->config("splitbytes");
        $self->debug( 5, "splitbytes is $splitbytes" );
    
        my (@parts) = $self->splitter($tarfile);
    
        foreach ( @parts ) {
            $self->debug( 9, "tarfile split part: $_" );
        }
    
        my(@checksum) = $self->create_checksum(@parts);
    
    
        unlink($ascfile);
        unless ( open(ASC,">>",$ascfile) ) {
            die("writing $ascfile: $!\n");
        }
    
        foreach ( @checksum ) {
            $self->debug( 9, "checksum: $_" );
            print ASC $_ . "\n";
        }
        close(ASC);
    
        # 
        # move splitfiles and asc file to diod and wait for completion
        # waiting for each file to vanish, i.e. moved to other side...
        #
        $self->debug( 9, "chdir($cwd)" );
        chdir($cwd) or die "chdir($cwd): $!\n";
    
        my($part);
        foreach $part ( @parts,$ascfile ) {
            $self->debug(9,"movin $part to diod");
            $self->mover($part);
            $self->wait_until_transfered($part) if ( $diodwait );
        }
    
        #
        # create and send som stats
        #
        my ($end)   = time;
        my($statsfh) = File::Temp->new();
        
        if ( $statsfh ) {
            $self->debug( 5, "saving some stats to " . $statsfh->filename  );
            my ($dur) = $end - $start;
            my ($i)   = 0;
            my ($pre) = "";
            if ($low) {
                $pre = "low";
            }
            else {
                $pre = "high";
            }
            print $statsfh $pre . "start=$start\n";
            print $statsfh $pre . "end=$end\n";
            print $statsfh $pre . "dur=$dur\n";
            print $statsfh $pre . "files=$files\n";
            print $statsfh $pre . "sent=$sent\n";
            print $statsfh $pre . "srv=" . hostname . "\n";
            print $statsfh $pre . "ver=$Transfer::VERSION\n";
        
            foreach ( sort keys %fileinfo ) {
                print $statsfh $pre . "file"
                . $i++ . "="
                . $_
                . ",$fileinfo{$_}\n";
            }
            close($statsfh);
            $self->debug( 5, "copy statsfile to $statsfile" );
            copy($statsfh->filename,$statsfile);
        }

        #
        # send debug log
        #
        my($debugsrc) = $self->taintfilename($self->get("debugname"));
        $self->debug(9,"copy debugfile to $debugfile");
        $self->debug(9,"Exiting low side");
        my($debugfh) = $self->get("debugfh");
        close($debugfh);
        copy($debugsrc,$debugfile);

        #
        # exit
        #
        print "Exiting low side...\n";
        exit(0);
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

    #if ( $size < $splitbytes ) {
    #    $self->debug( 5,
    #        "No need too split $srcfile $size is less then $splitbytes" );
    #    return (0);
    #}

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

    my(@parts) = ();
    my ($splitpath);
    my($totsize) = 0;
    foreach $splitpath (<$srcfile.part.*>) {
        push(@parts,$splitpath);
    }
    unlink($srcfile);
    return (@parts);
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


	#  0    1    2     3     4    5     6     7     8
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

	my($stamp) = sprintf("%04.4d%02.2d%02.2d_%02.2d:%02.2d:%02.2d", $year+1900, $mon +1, $mday, $hour, $min, $sec);

    chomp($msg);
    my ($str) = "$stamp DEBUG($level,$debug,$subroutine1:$line0): $msg";
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

