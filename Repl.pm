# File::Repl
#
# Version
#      $Source: D:/src/perl/File/Repl/RCS/Repl.pm $
#      $Revision: 1.8 $
#      $State: Exp $
#
# Start comments/code here - will not be processed into manual pages
#
#    Copyright © Dave Roberts  2000,2001
#
# Revision history:
#      $Log: Repl.pm $
#      Revision 1.8  2001/06/27 12:59:22  jj768
#      logic to prevent "Use of uninitialized value in pattern match (m//)" errors on use of $vol{FileSystemName}
#
#      Revision 1.6  2001/06/21 12:32:15  jj768
#      *** empty log message ***
#
#      Revision 1.5  2001/06/20 20:39:21  Dave.Roberts
#      minor header changes
#
#      Revision 1.4  2001/06/20 19:55:21  jj768
#      re-built module source files as per perlmodnew manpage
#
#
#******************************************************************************

package File::Repl;

require 5.005_62;
use strict;
use warnings;
use Carp;
use File::Find;
use File::Copy;
use File::Basename;
use constant FALSE                => 0;
use constant TRUE                 => 1;
use constant TIME_ZONE_ID_INVALID => 0xFFFFFFFF;
#**************************************************************
# On FAT filesystems, "stat" adds TZ_BIAS to the actual file
# times (atime, ctime and mtime) and "utime" subtracts TZ_BIAS
# from the supplied parameters before setting file times.  To
# maintain FAT at UTC time, we need to do the opposite.
#
# If we don't maintain FAT filesystems at UTC time and the repl
# is between FAT and NON-FAT systems, then all files will get
# replicated whenever the TZ or Daylight Savings Time changes.
#
# (NH270301)
#
my $TZ_BIAS = 0;               # global package variable
if ($^O eq 'MSWin32') {        # is this a win32 system ?
  eval "use Win32::API";
  eval "use Win32::AdminMisc";
  
  my $lpTimeZoneInformation = "\0" x 172;   # space for struct _TIME_ZONE_INFORMATION
  my $GetTimeZoneInformation = new Win32::API("kernel32", 'GetTimeZoneInformation', ['P'], 'N');
  croak "\n ERROR: failed to import GetTimeZoneInformation API function\n" if !$GetTimeZoneInformation;
  my $ISDST = $GetTimeZoneInformation->Call($lpTimeZoneInformation);
  croak "\n ERROR: GetTimeZoneInformation returned invalid data: " . Win32::FormatMessage(Win32::GetLastError())
  if $ISDST == TIME_ZONE_ID_INVALID;
  my ($Bias,$StandardBias,$DaylightBias) = unpack "l x80 l x80 l", $lpTimeZoneInformation;
  
# $ISDST == 0 -  No Daylight Savings in this timezone (no transition dates defined for this tz)
# $ISDST == 1 -  Standard time
# $ISDST == 2 -  Daylight Savings time
  
# bias times are returned in minutes - convert to seconds
  $TZ_BIAS = ($Bias + ($ISDST == 0 ? 0 : ($ISDST == 2 ? $DaylightBias : $StandardBias))) * 60;
}
#**************************************************************
require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use File::Repl ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
	
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	
);

our $VERSION = sprintf("%d.%d", q$Revision: 1.8 $ =~ /(\d+)\.(\d+)/);

# Preloaded methods go here.
#---------------------------------------------------------------------
sub New {
  my $class = shift;
  my($conf) = $_[0];
  croak "\n Usage: File::Repl->New(\$hashref)\n\n" unless (ref($conf) eq "HASH");
  
  my($alist,$blist,$atype,$btype,$key,$xxx,$dira,$dirb,$tmp);
  $conf->{dira} =~ s/\\/\//g;     # Make dir use forward slash's
  $conf->{dirb} =~ s/\\/\//g;     # Make dir use forward slash's
  
# To maintain backwards compatibility, check if additional
# keys are defined and default to a suitable value (NH271100)
  my $r_con = {
    dira     => $conf->{dira},
    dirb     => $conf->{dirb},
    verbose  => (defined $conf->{verbose}) ? $conf->{verbose} : 0,       # default not verbose
    agelimit => (defined $conf->{age})     ? $conf->{age}     : 0,       # default 0 (don't check age)
    ttl      => (defined $conf->{ttl})     ? $conf->{ttl}     : 31,      # default ttl 31 days
    nocase   => (defined $conf->{nocase})  ? $conf->{nocase}  : TRUE,    # default nocase TRUE
    bmark    => (defined $conf->{bmark})   ? $conf->{bmark}   : FALSE,   # default benchmark FALSE
    recurse  => (defined $conf->{recurse}) ? $conf->{recurse} : TRUE,    # default recurse TRUE
    mkdirs   => (defined $conf->{mkdirs})  ? $conf->{mkdirs}  : FALSE,   # default mkdirs FALSE
  };
  
# Added boolean 'recurse' key to hash and default to true if
# not defined. This allows faster build of file lists when
# only interested in top level directory.  (NH311000)
  my $recurse = $r_con->{recurse};
  
# Should we continue if dira / dirb dosn't exist ?  (NH301200)
  my $mkdirs = $r_con->{mkdirs};
  
  my $benchmark = $r_con->{bmark};
  
  if ( $r_con->{verbose} >= 3 ) {
    printf "\n\nFile:Repl configuration settings:\n";
    printf "-------------------------------\n";
    foreach $key (keys %$r_con ) {
      printf "  Key %-10s   Value %-30s\n",$key, $r_con->{$key};
    }
  }
  
# Build the A list
  benchmark("init") if $benchmark;
  if ( -d $r_con->{dira} ) {
    if ($recurse) {
      $xxx = sub{
        ($tmp = $File::Find::name) =~ s/^\Q$r_con->{dira}//;        # Remove the start directory portion
        ($atype->{$tmp}, $alist->{$tmp}) = (stat($_))[2,9] if $tmp; # Mode is 3rd element, mtime is 10th
      };
      find(\&$xxx,$r_con->{dira});
      }else{
      opendir(DIRA, "$r_con->{dira}") || croak "Can not open $r_con->{dira} directory !!!\n";
      while($tmp = readdir(DIRA)) {
        $tmp = "/" . $tmp;
        next if -d $r_con->{dira} . $tmp;                           # Skip directories
        ($atype->{$tmp}, $alist->{$tmp}) = (stat($r_con->{dira} . $tmp))[2,9];
      }
      close DIRA;
    }
    }elsif (!$mkdirs) {
    croak "Invalid directory name for dira ($r_con->{dira})\n";
  }
  benchmark("build A list") if $benchmark;
  
# Build the B list
  benchmark("init") if $benchmark;
  if ( $r_con->{dira} eq $r_con->{dirb} ) {
    $blist = $alist;
    $btype = $atype;
    }elsif ( -d $r_con->{dirb} ) {
    if ($recurse) {
      $xxx = sub{
        ($tmp = $File::Find::name) =~ s/^\Q$r_con->{dirb}//;        # Remove the start directory portion
        ($btype->{$tmp}, $blist->{$tmp}) = (stat($_))[2,9] if $tmp; # Mode is 3rd element, mtime is 10th
      };
      find(\&$xxx,$r_con->{dirb});
      }else{
      opendir(DIRB, "$r_con->{dirb}") || croak "Can not open $r_con->{dirb} directory !!!\n";
      while($tmp = readdir(DIRB)) {
        $tmp = "/" . $tmp;
        next if -d $r_con->{dirb} . $tmp;                           # Skip directories
        ($btype->{$tmp}, $blist->{$tmp}) = (stat($r_con->{dirb} . $tmp))[2,9];
      }
      close DIRB;
    }
    }elsif (!$mkdirs) {
    croak "Invalid directory name for dirb ($r_con->{dirb})\n";
  }
  benchmark("build B list") if $benchmark;
  
  $r_con->{alist} = \$alist;
  $r_con->{atype} = \$atype;
  $r_con->{blist} = \$blist;
  $r_con->{btype} = \$btype;
  
  bless  $r_con, $class;
  return $r_con;
}
#=====================================================================
sub Update {
  return _generic ("Update",@_);
}
#=====================================================================
sub Rename {
  return _generic ("Rename",@_);
}
#=====================================================================
sub Process {
  if ( scalar(@_) eq 3 ) {
    my($r_con,$regex,$sub) =@_;
    my($negregex) = '^$';   # Make this impossible to match, nor file or directory
# can be of zero length name.
    }elsif ( scalar(@_) eq 4 ) {
    my($r_con,$regex,$negregex,$sub) =@_;
    }else{
    carp ("Try calling the File::Repl->Process method with the right arguments !\n");
  }
  print "The Process method is not implemented\n";
}
#=====================================================================
sub Compress {
  if ( scalar(@_) eq 3 ) {
    my($r_con,$regex,$archive) =@_;
    my($negregex) = '^$';   # Make this impossible to match, nor file or directory
# can be of zero length name.
    }elsif ( scalar(@_) eq 4 ) {
    my($r_con,$regex,$negregex,$mode,$commit) =@_;
    }else{
    carp ("Try calling the File::Repl->Compress method with the right arguments !\n");
  }
  print "The Compress method is not implemented\n";
}
#=====================================================================
sub Delete {
  return _generic ("Delete",@_);
}
#=====================================================================

sub _generic {
  
  my ($caller) = shift @_;
  my($r_con,$regex,$mode,$commit,$nsub);
  my($refa,$refb,$refatype,$refbtype,$agelimit,$verbose);
  my($name,$mtime,%mark,$afile,$bfile,$amtime,$bmtime,$fc,$md,$del,$type);
  my(@amatch,@bmatch,$benchmark,$tfiles,$common,$aonly,$bonly,$amatch,@temp,%vol);
  my($tName,$aName,$bName,$deltree,$truncate,$touch,$rename,$tmp,$atype,$btype);
  my ($negregex) = '^$';# Default value - make this impossible to match, neither file nor directory
  my $tz_bias_a = 0;
  my $tz_bias_b = 0;
  
# On FAT filesystems, mtime resolution is 1/30th of a second.
# Increase fudge to 2 to allow for A <> DOS <> B e.g. syncing
# two machines via a zip disk  (NH311000)
  my $fudge = 2;
  
  if ($caller eq "Update") {
    if ( scalar(@_) == 4 ) {
      ($r_con,$regex,$mode,$commit) = @_;
      }elsif ( scalar(@_) == 5 ) {
      ($r_con,$regex,$negregex,$mode,$commit) = @_;
      }else{
      carp ("Call the Update method with the right arguments !\n\t\$ref->Update(regex, [noregex,] action, commit)");
      print scalar(@_), " Args called ( @_ )\n";
      return;
    }
    $mode      = 'a>b' if ( $mode eq "" );      # Set the default operating mode
    }elsif($caller eq "Delete"){
    if ( scalar(@_) eq 3 ) {
      ($r_con,$regex,$commit) =@_;
# can be of zero length name.
      }elsif ( scalar(@_) eq 4 ) {
      ($r_con,$regex,$negregex,$commit) =@_;
      }else{
      carp ("Call the Delete method with the right arguments !\n\t\$ref->Delete(regex, [noregex], commit)");
    }
    }elsif($caller eq "Rename"){
    if ( scalar(@_) eq 4 ) {
      ($r_con,$regex,$nsub,$commit) =@_;
# can be of zero length name.
      }elsif ( scalar(@_) eq 5 ) {
      ($r_con,$regex,$negregex,$nsub,$commit) =@_;
      }else{
      carp ("Call the Rename method with the right arguments !\n\t\$ref->Rename(regex, [noregex], namesub, commit)");
    }
  }
   
  
  my $nocase = $r_con->{nocase};
  
# Expiry time for tombstone indicator files in seconds
  my $ttl = $r_con->{ttl} * 60 * 60 * 24;
   
  $commit    = TRUE unless defined $commit;   # Set default commit value
  $verbose   = $r_con->{verbose};
  $agelimit  = $r_con->{agelimit} ? $r_con->{agelimit} * 86400 : 0;
  $benchmark = $r_con->{bmark};
  
# Fix for stat/utime on FAT filesystems (NH270301)
  if ($TZ_BIAS) {
    if ( %vol = Win32::AdminMisc::GetVolumeInfo( $r_con->{dira} )){
      $tz_bias_a = $TZ_BIAS if ($vol{FileSystemName} =~ m/FAT/);
    }
    if ( %vol = Win32::AdminMisc::GetVolumeInfo( $r_con->{dirb} )){
      $tz_bias_b = $TZ_BIAS if ($vol{FileSystemName} =~ m/FAT/);
    }
    $tz_bias_a = $tz_bias_b = 0 if ($tz_bias_a && $tz_bias_b);
  }
  
  if ($verbose >= 3) {
    print "Update\n  Regex    : $regex\n  NegRegex : $negregex\n";
    print "  Mode     : $mode\n  Commit   : $commit\n";
    print "  AgeLimit : $r_con->{agelimit}  ($agelimit)\n";
    print "  Tombstone File TTL : $ttl\n";
    print "  DirA DOS time adj : $tz_bias_a\n";
    print "  DirB DOS time adj : $tz_bias_b\n\n";
  }
# Ensure no matches if $negregex = ''
  $negregex = '^$' unless $negregex;
  
# Sort files using regex and negregex
  benchmark("init") if $benchmark;
  ($tfiles,$common,$aonly,$bonly,$amatch,$refa,$refb,$refatype,$refbtype) =
  _arraysort($r_con, $regex, $negregex, $nocase) ;
  benchmark("match files") if $benchmark;
#****************************************************************
# sub to copy files and build directory structure
#****************************************************************
  $fc = sub {
    my($a,$b,$amtime,$bmtime,$mode) = @_;
    my($btmp);
    
# Ignore the file if agelimit is switched on and file exceeds
# this
    if ( $agelimit && (( time - $amtime ) > $agelimit )) {
      print " $a ignored - exceeds age limit \n" if $verbose > 1;
      return FALSE;
    }
    return TRUE unless $commit;
    
# Make sure the parent of the target file exists
    return FALSE unless &$md(dirname($b));
    
    if ( -f $a ) {
      if ( -f $b ) {
# If we have a file to copy, and we are replacing a previous version create a filename
# that we can rename the previous version to.
        $btmp = $b . '.X';
        while ( -f $btmp ) {
          $btmp .= 'X';
          print " *************** $btmp\n";
        }
# rename old copy of $b - to restore if the copy fails
        unless ( rename ($b, $btmp) ) {
          carp "Unable to create temp copy of $b ($btmp) \n";
          undef $btmp;
        }
      }
      
      if ( copy ($a,$b) ) {
# ******
# this needs modifying for UNIX
        chmod(0666,$b) if !($mode & 0x02);
        utime($amtime,$amtime,$b) || carp "Failed to set modification time on $b\n";
        chmod(0444,$b) if !($mode & 0x02);
# ******
        if ( $btmp ) {
# If we had renamed a previous version of file (for potential recovery) we
# delete it now.
          unlink $btmp || carp "Failed to delete temporary file $btmp\n";
        }
        return TRUE;
        }else{
        carp "unable to copy $a\n";
        if ( $btmp ) {
# If we had renamed a previous version of file (for potential recovery) we
# restore it now
          unless ( rename ($btmp, $b) ) {
            carp "Unable to restore $b from temp copy of $btmp following failed file copy\n";
            undef $btmp;
          }
        }
      }
      }else{
      if ( ! -d $b ) {
        mkdir($b,0777) && return TRUE || carp "Unable to create directory $b\n";
      }
#  setting utime doe'nt work on a dir.  Maybe FS rules ??
#utime($amtime,$amtime,$b) || carp "Failed to set modification time on $b\n";
#my($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat($b);
#print " A mtime $amtime\n B mtime $mtime\n";
    }
    return FALSE;
  };
  
#****************************************************************
# sub to test a directory tree exists, and if not to create it
#****************************************************************
  $md = sub {
    my($Dir) = @_;
    return TRUE unless $commit;
    if (! -d $Dir) {
      $Dir =~ /(.*)\/([^\/]*)/;
      my($parent,$dir) = ($1,$2);
      &$md($parent) if (!-d $parent);  # Create the parent if it does not exist
      mkdir ($Dir, 0777) || carp "Unable to create directory $Dir\n";
    }
    return(-d $Dir);
  };
  
#****************************************************************
# sub to delete directories / files
#****************************************************************
  $del = sub {
    my($targ, $mtime) = @_;
    if ($verbose >= 1) {
      (-d $targ) ? print "  rmdir  $targ\n" : print "  remove $targ\n";
    }
    if ( $mtime && $agelimit && (( time - $mtime ) > $agelimit )) {
      if ( $verbose >= 1 ) {
        print "$a ignored - exceeds age limit -";
      printf "   (%3.1d days old - limit set is %3d days))\n", (time - $mtime)/(86400), $agelimit/(86400);
    }
    return FALSE;
  }
  return TRUE unless $commit;
  if (-d $targ) {
    rmdir $targ || carp "Unable to delete directory $targ\n";
    return ! -d $targ;
    }elsif (-f $targ) {
    unlink $targ || carp "Unable to delete file $targ\n";
    return ! -f $targ;
    }else{
    print "** DO SOMETHING HERE ** (NOT ORDINARY FILE OR DIRECTORY)\n";
# should do something here ???
# UNIX links ???
  }
  return FALSE;
};

#****************************************************************
# sub to delete directory trees
#****************************************************************
$deltree = sub {
  my($targ,$dir,$reftime,$reftype,$top) = @_;
  my $xxx = sub {
    ($tmp = $File::Find::name) =~ s/^\Q$dir//;      # Remove the start directory portion
    return if (!$top && !rindex($tmp, '/'));        # Don't remove top level directory unless $top == TRUE
    chdir $dir if !rindex($tmp, '/');               # Move up to parent if removing top level dir
    delete $$reftime->{$tmp}, delete $$reftype->{$tmp} if &$del($File::Find::name);
  };
  finddepth(\&$xxx, $dir . $targ);
  return if $top;
  $commit ? $$reftime->{$targ} = (stat($dir . $targ))[9] : $$reftime->{$targ} = time;
};

#****************************************************************
# sub to truncate files to zero length
#****************************************************************
$truncate = sub {
  my($file_ref, $mtime_ref) = @_;
  print " truncate $$file_ref\n" if ($verbose >= 2);
  if ($commit) {
    chmod(0666,$$file_ref)  || carp "Failed to chmod 0666 $$file_ref\n";
    truncate($$file_ref, 0) || carp "Failed to truncate $$file_ref\n";
  }
  $$mtime_ref = $commit ? (stat($$file_ref))[9] : time;
  $$file_ref = undef;
  return TRUE;
};

#****************************************************************
# sub to touch files
#****************************************************************
$touch = sub {
  my($file, $mtime_ref, $type_ref) = @_;
  print "   touch $file\n" if ($verbose >= 2);
  if ($commit) {
    open(FILE, ">> $file") || carp "Failed to touch $file\n";
    close(FILE);
  }
  ($$type_ref, $$mtime_ref) = $commit ? (stat($file))[2,9] : time;
};
#****************************************************************
# sub to rename a file or directory
#****************************************************************
$rename = sub {
  my($old,$new) = @_;
  return TRUE unless $commit;
  if ( rename ($old,$new)) {
    return TRUE;
  }
  return FALSE;
};

benchmark("init") if $benchmark;
if ( $caller eq "Update" ) {
#****************************************************************
# Delete tombstoned files (NH261100)
#****************************************************************
  foreach $tName (@$tfiles) {
    ($name = $tName) =~ s/.remove$//i;
    
# Delete <dir.remove> trees and touch a file with same name
    if (-d $r_con->{dira} . $tName) {
      &$deltree($tName, $r_con->{dira}, $refa, $refatype, TRUE);
      &$touch($r_con->{dira} . $tName, \$$refa->{$tName}, $$refatype->{$tName});
    }
    if (-d $r_con->{dirb} . $tName) {
      &$deltree($tName, $r_con->{dirb}, $refb, $refbtype, TRUE);
      &$touch($r_con->{dirb} . $tName, \$$refb->{$tName}, $$refbtype->{$tName});
    }
    
# Delete <dir> trees and files
    if ($nocase) {
      ($aName) = grep { /^$name$/i } (keys %$$refa);
      ($bName) = grep { /^$name$/i } (keys %$$refb);
      }else{
      $aName = ($$refa->{$name}) ? $name : undef;
      $bName = ($$refb->{$name}) ? $name : undef;
    }
    if ($aName) {
      if (-d $r_con->{dira} . $aName) {
# Delete dir trees including top level dir
        &$deltree($aName, $r_con->{dira}, $refa, $refatype, TRUE);
        }else{
        delete $$refa->{$aName}, delete $$refatype->{$aName} if &$del($r_con->{dira} . $aName);
      }
    }
    if ($bName) {
      if (-d $r_con->{dirb} . $bName) {
# Delete dir trees including top level dir
        &$deltree($bName, $r_con->{dirb}, $refb, $refbtype, TRUE);
        }else{
        delete $$refb->{$bName}, delete $$refbtype->{$bName} if &$del($r_con->{dirb} . $bName);
      }
    }
  }
#****************************************************************
# Remove tombstone indicator files if older than $ttl (NH261100)
# Truncate (which will also touch) nonzero byte files (NH070401)
#****************************************************************
  foreach (@$tfiles) {
    $afile = $$refa->{$_} ? $r_con->{dira} . $_ : undef;
    $bfile = $$refb->{$_} ? $r_con->{dirb} . $_ : undef;
    &$truncate(\$afile, \$$refa->{$_}) if ($afile && -s $afile);
    &$truncate(\$bfile, \$$refb->{$_}) if ($bfile && -s $bfile);
    delete $$refa->{$_}, delete $$refatype->{$_} if ($afile && (($$refa->{$_} + $ttl) < time) && &$del($afile));
    delete $$refb->{$_}, delete $$refbtype->{$_} if ($bfile && (($$refb->{$_} + $ttl) < time) && &$del($bfile));
  }
  
  if ( $mode =~ /^(A>B)|(A<>B)$/ ) {
    foreach (@$aonly) {
      next unless exists $$refa->{$_};
      $afile  = $r_con->{dira} . $_;
      $amtime = $$refa->{$_} - $tz_bias_a + $tz_bias_b;
      $atype  = $$refatype->{$_};
      $bfile  = $r_con->{dirb} . $_;
      print " $afile --> $bfile\n" if ($verbose >= 1);
      $$refb->{$_} = $amtime, $$refbtype->{$_} = $$refatype->{$_}
      if &$fc($afile,$bfile,$amtime,"",$atype);
    }
  }
  if ( $mode =~ /^(A<B)|(A<>B)$/ ) {
    foreach (@$bonly) {
      next unless exists $$refb->{$_};
      $afile  = $r_con->{dira} . $_;
      $bfile  = $r_con->{dirb} . $_;
      $bmtime = $$refb->{$_} - $tz_bias_b + $tz_bias_a;
      $btype  = $$refbtype->{$_};
      print " $afile <-- $bfile\n" if ($verbose >= 1);
      $$refa->{$_} = $bmtime, $$refatype->{$_} = $$refbtype->{$_}
      if &$fc($bfile,$afile,$bmtime,"",$btype);
    }
  }
  if ( $mode =~ /^A<B!$/ ) {
    foreach (@$aonly) {
      next unless exists $$refa->{$_};
      $afile  = $r_con->{dira} . $_;
      $amtime = $$refa->{$_};
      delete $$refa->{$_}, delete $$refatype->{$_} if &$del($afile, $amtime);
    }
  }
  if ( $mode =~ /^A>B!$/ ) {
    foreach (@$bonly) {
      next unless exists $$refb->{$_};
      $bfile  = $r_con->{dirb} . $_;
      $bmtime = $$refb->{$_};
      delete $$refb->{$_}, delete $$refbtype->{$_} if &$del($bfile, $bmtime);
    }
  }
  foreach $aName (keys %$common) {
    next unless exists $$refa->{$aName};
# To allow for non case sensitive filesystems
# %common key holds the 'a' name and
# %common value holds the 'b' name
    $bName  = $$common{$aName};
    $amtime = $$refa->{$aName} - $tz_bias_a;
    $bmtime = $$refb->{$bName} - $tz_bias_b;
    $atype  = $$refatype->{$aName};
    $btype  = $$refbtype->{$bName};
    $afile  = $r_con->{dira} . $aName;
    $bfile  = $r_con->{dirb} . $bName;
    
# Skip directories as their time can't be set (NH251100)
    next if -d $afile;
    
    if ( $amtime > ($bmtime + $fudge) ) {
      $amtime += $tz_bias_b;
      if ( $mode =~ /^(a>b)|(a<>b)|(A>B)|(A>B!)|(A<>B)$/ ) {
        if ( -f $afile ) {
          print " $afile --> $bfile\n" if ($verbose >= 1);
          print "  ($amtime) --> ($bmtime)\n" if ($verbose >= 2);
        }
        $$refb->{$bName} = $amtime if (&$fc($afile,$bfile,$amtime,$bmtime,$atype));
      }
      }elsif ( ($amtime + $fudge) < $bmtime ) {
      $bmtime += $tz_bias_a;
      if ( $mode =~ /^(a<b)|(a<>b)|(A<B)|(A<B!)|(A<>B)$/ ) {
        if ( -f $afile ) {
          print " $afile <-- $bfile\n" if ($verbose >= 1);
          print "  ($amtime) <-- ($bmtime)\n" if ($verbose >= 2);
        }
        $$refa->{$aName} = $bmtime if (&$fc($bfile,$afile,$bmtime,$amtime,$btype));
      }
    }
  }
  }elsif( $caller eq "Delete" ) {
  foreach my $f (@$amatch) {
    next unless exists $$refa->{$f};
    $afile  = $r_con->{dira} . $f;
    $amtime = $$refa->{$f} - $tz_bias_a + $tz_bias_b;
    $atype  = $$refatype->{$f};
    print " rm $afile\n" if ($verbose >= 1);
    if (&$del($afile, $amtime)) {
      if ($commit) {
        delete $$refa->{$f};
        delete $$refatype->{$f};
# remove reference to this file from the arrays @aonly etc.
      }
    }
  }
  }elsif( $caller eq "Rename" ) {
  foreach my $f (@$amatch) {
    next unless exists $$refa->{$f};
    my($newname) = $f;
    if ( $nsub =~ /^([.])(.*)($1)(.*)($1)(.*)$/ ) {
      my($sep,$match,$replace,$arg) = ($1,$2,$4,$5);
      $newname =~ s/$match/$match/;
      $afile  = $r_con->{dira} . $f;
      my ($Afile) = $r_con->{dira} . $newname;
      print " mv $afile $Afile\n" if ($verbose >= 1);
      if (&$rename($afile,$Afile)){
        if ( $commit ) {
          $$refa->{$Afile}     = $$refa->{$f};
          $$refatype->{$Afile} = $$refatype->{$f};
          delete $$refa->{$f};
          delete $$refatype->{$f};
# remove reference to this file from the arrays @aonly etc.
        }
      }
      }else{
      carp "unable to understand substition argument $nsub\n";
    }
  }
}

benchmark("synch files") if $benchmark;
}

#=====================================================================
# Support old method call
sub SetDefaults {
return New @_;
}
#=====================================================================
sub _arraysort {
my($r_con, $regex, $negregex, $nocase) = @_;
my(@amatch,@bmatch,@tfiles,%common,@aonly,@bonly,@temp,$name,$mtime,$type);
my(@sorted_amatch,@sorted_bmatch,$aName,$bName,$aIndex,$bIndex);
my %dup      = ();
my $verbose  = $r_con->{verbose};
my $refa     = $r_con->{alist};
my $refatype = $r_con->{atype};
my $refb     = $r_con->{blist};
my $refbtype = $r_con->{btype};

# If dealing with case insensitive filesystems, use regex
# extention (?i) on pattern matching    (NH181200)
my $regexextn = $nocase ? '(?i)' : '';

# Find files matching the regex in dira
print "Files Matching regex in $r_con->{dira}:\n" if ($verbose >= 4);
foreach $name (keys %$$refa) {
  if ( $name && ($name =~ /$regexextn$regex/) && ($name !~ /$regexextn$negregex/) ) {
    push (@amatch,$name);
    if ($verbose >= 4) {
      $mtime = %$$refa->{$name};
      $type  = %$$refatype->{$name};
      print "  $mtime  $type  $name\n";
    }
  }
}
# Find files matching the regex in dirb
print "Files Matching regex in $r_con->{dirb}:\n" if ($verbose >= 4);
foreach $name (keys %$$refb) {
  if ( $name && $name =~ /$regexextn$regex/ && $name !~ /$regexextn$negregex/ ) {
    push (@bmatch,$name);
    if ($verbose >= 4) {
      $mtime = %$$refb->{$name};
      $type  = %$$refbtype->{$name};
      print "  $mtime  $type  $name\n";
    }
  }
}

# Build a list of files that have an added extension ".remove"
# These indicate tombstoned files that will be deleted from
# all replications.     (NH261100)
@tfiles =     grep { /.+\.remove$/i } @amatch;  # get alist files
push @tfiles, grep { /.+\.remove$/i } @bmatch;  # get blist files
@tfiles =     grep { ! $dup{$_} ++  } @tfiles;  # remove dups

# Find elements that are common/unique to @amatch and @bmatch
# -put in sorted order so that we can create directories/files
#  in one sweep (ie we don't try to create a file before its
#  parent directory exists)
#
# On non-case sensitive filesystems (e.g Bill's) ignore the case
# when testing for matching files.  This will still allow repl to
# create / update files maintaining their original case. (NH311000)
$aIndex = 0;
$bIndex = 0;
@sorted_amatch = $nocase ? sort {lc($a) cmp lc($b) } @amatch : sort @amatch;
@sorted_bmatch = $nocase ? sort {lc($a) cmp lc($b) } @bmatch : sort @bmatch;

while ( $aIndex < @sorted_amatch ) {
  last unless defined $sorted_bmatch[$bIndex];  # End of b list
  $aName = $sorted_amatch[$aIndex];
  $bName = $sorted_bmatch[$bIndex];
  if ($aName eq $bName || ($nocase && lc($aName) eq lc($bName))) {
    $common{$aName} = $bName;  # Store $aName as key and $bName as value
    $aIndex++;
    $bIndex++;
  }
  elsif (($nocase && lc($aName) lt lc($bName)) || (!$nocase && $aName lt $bName)) {
    push(@aonly,$aName);
    $aIndex++;
  }
  else {
    push(@bonly,$bName);
    $bIndex++;
  }
}
# Get any remainder of 'a' list
while ( $aIndex < @sorted_amatch ) {
  push(@aonly,$sorted_amatch[$aIndex++]);
}
# Get any remainder of 'b' list
while ($bIndex < @sorted_bmatch) {
  push(@bonly,$sorted_bmatch[$bIndex++]);
}

# Sort @aonly and @bonly - so that directories are allways processed after files they contain
# This way we delete the directory only after its empty

@aonly = reverse sort @aonly;
@bonly = reverse sort @bonly;

if ( $verbose >= 3 ) {
  print "Common Files :\n";
  foreach (keys %common) {
    print "  $_\n  $common{$_}\n";
  }
  print "A dir only Files :\n";
  foreach (@aonly) {
    print "  $_\n";
  }
  print "B dir only Files :\n";
  foreach (@bonly) {
    print "  $_\n";
  }
  print "Replicating ...\n";
}
return (\@tfiles, \%common, \@aonly, \@bonly, \@amatch, $refa,$refb,$refatype,$refbtype);
}
#=====================================================================
my @times; # global var
sub benchmark ($@) {
my($str,$r1,$u1,$s1) = @_;
@times = $r1 ? ($r1,$u1,$s1) : (time, times), return if $str eq "init";
($r1,$u1,$s1)   = @times unless $r1;
my($r2,$u2,$s2) = (time, times);
printf "  %-13s: %2d secs  ( %.2f usr + %.2f sys = %.2f CPU )\n",
$str, $r2-$r1, $u2-$u1, $s2-$s1, $u2-$u1 + $s2-$s1;
}
#=====================================================================

1;
__END__

=head1 NAME

File::Repl - Perl module that provides file replication utilities

=head1 SYNOPSIS

  use File::Repl;

  %con = {
    dira     => 'D:/perl',
    dirb     => 'M:/perl',
    verbose  => '1',
    age      => '10',
  };

  $ref=File::Repl->New(\%con);
  $ref->Update('\.p(l|m)','a<>b',1);
  $ref->Update('\.t.*','a<>b',1,'\.tmp$');

=head1 DESCRIPTION

The File:Repl provides simple file replication and management utilities. Its main
functions are

=over 4

=item File Replication

Allowing two directory structures to be maintained, ensuring files that meet
selection logic criteria are mirrored and otherwise synchronized.

=item Bulk Renaming

Allowing files in a directory structure to be renamed according to the selection
logic.

=item Compressing

Allowing files in a directory structure to be compressed according to a given logic.

=item Process

Run a common perl process against files in a directory structure according to selection
logic.

=item Deletion

Allowing files in a directory structure to be deleted according to the selection
logic.

=back

=head1 METHODS

=over 2

=item B<New(%con)>

The B<New> method constructs a new File-Repl object.  Options are passed in the form of a hash
reference I<\%con> which define the file directories to be operated on and other parameters.
The directories are scanned and each file is stat'ed.   The hash keys have the following definitions-

=over 4

=item dira

This identifies the first directory to be scanned (required).

=item dirb

This identifies the second directory to be scanned (required).  If the object is only to
have methods operate on it that operate on a single directory then dirb can be set to the
same value as dira.  This minimizes the directory structure to be sesarched.

=item verbose

The verbose flag has several valid values:

=over 8

=item 0

No verbosity (default mode).

=item 1

All file copies and deletes are printed.

=item 2

Tombstone file trunkations are printed, and any timestamp changes made,

=item 3

Configuration settings (from I<%con>) and Files meeting the match criteria are printed.

=item 4

Files identified in each directory that match the regex requirements (from the B<Update>
method) are printed.

=back

=item age

This specifies the  maximum age of a file in days.  Files older than this will
be ignored by Update, Rename, Compress and Delete methods.

=item recurse

When set to FALSE only files at the top level of the B<dira> and B<dirb> are scanned. Default
value is

=item ttl

This is the time to live (B<ttl> for any tombstoned file, in days.  Default value is 31.

=item nocase

Switches for case sensitivity - default is TRUE (case insensitive).

=item mkdirs

If either directory B<dira> or B<dirb> do not exist will attempt to create the directory
if set TRUE.  Default value is FALSE.


=back

=item B<Update(regex, [noregex,] action, commit)>

The B<Update> method makes the file updates requested - determined by the I<%con>
hash (from the B<New> method) and four associated arguments.

This method also allows
files to be tombstoned (ie removed from the replicated file sets).  A file is tombstoned
by appending I<.remove> to the file name.  The first B<Update> will cause the file to be
set to zero size, and any replica files to be renamed (so the original file does not
return).  The next update after the B<ttl> has expired will cause deletion of all file
replicas.

If a directory is tombstoned (by adding I<.remove> to its name) the directory and contents
are removed and a file with the directory name and the I<.remove> suffix replaces it.  The
file is removed as a normally tombstoned file.

=over 0

=item B<regex>

A regular expression, used to match all file names that are to be maintained.

=item B<noregex>

An optional regular expression used to match all files not to be maintained
(ie excluded from the operation).

=item B<action>

defines the action to be performed.

=over 4

=item a>b

Files in the 'a' directory are to be replicated to the 'b' directory
if a replica exists in 'b' directory and the timestamp is older than that
of the file in the 'a' directory.

=item a<b

Files in the 'b' directory are to be replicated to the 'a' directory
if a replica exists in 'a' directory and the timestamp is older than that
of the file in the 'b' directory.

=item a<>b

Files in the 'a' directory are to be replicated to the 'b' directory
if a replica exists in 'b' directory and the timestamp is older than that
of the file in the 'a' directory.  Files in the 'b' directory are to be
replicated to the 'a' directory if a replica exists in 'a' directory and
the timestamp is older than that of the file in the 'b' directory.

=item A>B

Files in the 'a' directory are to be replicated to the 'b' directory
- even if no replica exists in 'b' directory.  If a replica already exists
in the 'b' directory with a timestamp that is newer than that of the file
in the 'a' directory it is not modified.

=item A>B!

Files in the 'a' directory are to be replicated to the 'b' directory
- even if no replica exists in 'b' directory.  If a replica already exists
in the 'b' directory with a timestamp that is newer than that of the file
in the 'a' directory it is not modified.  Orphan files in the 'b'
directory are deleted.

=item AE<lt>B

Files in the 'b' directory are to be replicated to the 'a' directory
- even if no replica exists in 'a' directory.  If a replica already exists
in the 'a' directory with a timestamp that is newer than that of the file
in the 'b' directory it is not modified.

=item AE<lt>B!

Files in the 'b' directory are to be replicated to the 'a' directory
- even if no replica exists in 'a' directory.  If a replica already exists
in the 'a' directory with a timestamp that is newer than that of the file
in the 'b' directory it is not modified. Orphan files in the 'a'
directory are deleted.

=item AE<lt>>B

Files in the 'a' directory are to be replicated to the 'b' directory
- even if no replica exists in 'b' directory.  If a replica already exists
in the 'b' directory with a timestamp that is newer than that of the file
in the 'a' directory it is not modified. Files in the 'b' directory are to
be replicated to the 'a' directory - even if no replica exists in 'a'
directory.  If a replica already exists in the 'a' directory with a
timestamp that is newer than that of the file
in the 'b' directory it is not modified.

=back

=item commit

When set TRUE makes changes required - set FALSE to show potential changes
(which are printed to STDOUT)

=back

=item B<Rename(regex, [noregex], namesub, commit)>

The B<Rename> method is used to rename files in the I<dira> directory structure
in the object specified in the B<New> method.

=over 0

=item regex

A regular expression, used to match all file names that are to be renamed.

=item noregex

An optional regular expression used to match all files not to be renamed
(ie excluded from the operation).

=item namesub

The argument used for a perl substitution command is applied to the file name
to create the file's new name.

e.g. /\.pl$/\.perl\$/

This examplewill rename all files (that meet I<regex> and I<noregex> criteria)
from .pl to .perl

=item commit

When set TRUE makes renames required - set FALSE to show potential changes
(which are printed to STDOUT)

=back

=item B<Process>

Not yet implemeneted

=item B<Compress>

Not yet implemented

=item B<Delete(regex, [noregex], commit)>

The B<Delete> method removes files from the I<dira> directory structure in the object
specified in the B<New> method.

=over 0

=item B<regex>

A regular expression, used to match all file names that are to be deleted.

=item B<noregex>

An optional regular expression used to match all files not to be deleted
(ie excluded from the operation).

=item commit

When set TRUE makes deletions required - set FALSE to show potential changes
(which are printed to STDOUT)

=back

=head1 REQUIRED MODULES

  File::Find;
  File::Copy;
  File::Basename;

  Win32::AdminMisc (Win32 platforms only)
  Win32::API       (Win32 platforms only)

=head1 TIMEZONE AND FILESYSTEMS

On FAT filesystems, mtime resolution is 1/30th of a second.  A fudge of 2 seconds
is used for synching FAT with other filesystems.  Note that FAT filesystems
save the local time in UTC (GMT).

On FAT filesystems, "stat" adds TZ_BIAS to the actual file times (atime, ctime and
mtime) and conversley "utime" subtracts TZ_BIAS from the supplied parameters before
setting file times.  To maintain FAT at UTC time, we need to do the opposite.

If we don't maintain FAT filesystems at UTC time and the repl is between FAT and
NON-FAT systems, then all files will get replicated whenever the TZ or Daylight
Savings Time changes.


=head1 AUTHOR

Dave Roberts



=head1 SUPPORT

You can send bug reports and suggestions for improvements on this module
to me at DaveRoberts@iname.com. However, I can't promise to offer
any other support for this script.

=head1 COPYRIGHT

This module is Copyright © 2000, 2001 Dave Roberts. All rights reserved.

This script is free software; you can redistribute it and/or modify it
under the same terms as Perl itself. This script is distributed in the
hope that it will be useful, but WITHOUT ANY WARRANTY; without even
the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
PURPOSE. The copyright holder of this script can not be held liable
for any general, special, incidental or consequential damages arising
out of the use of the script.

=head1 CHANGE HISTORY

$Log: Repl.pm $
Revision 1.8  2001/06/27 12:59:22  jj768
logic to prevent "Use of uninitialized value in pattern match (m//)" errors on use of $vol{FileSystemName}

Revision 1.6  2001/06/21 12:32:15  jj768

*** empty log message ***

Revision 1.5  2001/06/20 20:39:21  Dave.Roberts
minor header changes

Revision 1.4  2001/06/20 19:55:21  jj768
re-built module source files as per perlmodnew manpage

Revision 1.1  2001/06/20 19:53:03  Dave.Roberts
Initial revision

Revision 1.3.5.0  2001/06/19 10:34:11  jj768
Revised calling of the New method to use a hash reference, rather
than a hash directly

Revision 1.3.4.0  2001/06/19 09:48:38  jj768
intermediate development revision.  Introduced Delete method and the _generic
subroutine (used for all methods except New)
this is preparatory to the hash being passed as a reference

Revision 1.3.3.0  2001/06/14 15:42:48  jj768
minor code changes in constructing hash and improvement in documentation
-still need more docs on Timezones.


=cut
