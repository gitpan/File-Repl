package File::Repl;

use strict;
use Carp;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK $AUTOLOAD);
use File::Find;
use File::Copy;
use File::Basename;

require Exporter;
require DynaLoader;
require AutoLoader;

@ISA = qw(Exporter DynaLoader);
# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.
@EXPORT = qw();
@EXPORT_OK = qw();
$VERSION = '0.04';

sub AUTOLOAD {
# This AUTOLOAD is used to 'autoload' constants from the constant()
# XS function.  If a constant is not found then control is passed
# to the AUTOLOAD in AutoLoader.
  
  my $constname;
  ($constname = $AUTOLOAD) =~ s/.*:://;
  croak "& not defined" if $constname eq 'constant';
  my $val = constant($constname, @_ ? $_[0] : 0);
  if ($! != 0) {
    if ($! =~ /Invalid/) {
      $AutoLoader::AUTOLOAD = $AUTOLOAD;
      goto &AutoLoader::AUTOLOAD;
    }
    else {
      croak "Your vendor has not defined dnstoolc macro $constname";
    }
  }
  *$AUTOLOAD = sub () { $val };
  goto &$AUTOLOAD;
}


#bootstrap dnstoolc $VERSION;

# Preloaded methods go here.

#---------------------------------------------------------------------
sub SetDefaults {
  my(%conf) = @_;
  my($alist,$blist,$key,$xxx);
  $conf{dira} =~ s/\\/\//g;     # Make dir use forward slash's
  $conf{dirb} =~ s/\\/\//g;     # Make dir use forward slash's

  my $r_con = {
    'dira',      $conf{dira},
    'dirb',      $conf{dirb},
    'verbose',   $conf{verbose}
  };
  if ( $conf{verbose} >= 2 ) {
    printf "\n\File:Repl configuration settings:\n";
    printf "-------------------------------\n";
    foreach $key (keys %conf ) {
      printf "  Key %-10s   Value %-30s\n",$key, $$r_con{$key};
    }
  }
  $xxx = sub{
    my($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat($_);
    my($tmp) = $File::Find::name;
    my($tmp2) = $r_con->{dira};
    $tmp2 =~ s/\$/\\\$/g;     # Backslash any $ in $r_con->{dira}
    $tmp =~ s/$tmp2//g;       # Remove the directory portion
    $alist->{$tmp} = $mtime;
  };
  if ( -d $r_con->{dira} ) {  find(\&$xxx,$r_con->{dira});
  }else{
    croak "Invalid directory name for dira ($r_con->{dira})\n";
  }
  $xxx = sub{
    my($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat($_);
    my($tmp) = $File::Find::name;
    my($tmp2) = $r_con->{dirb};
    $tmp2 =~ s/\$/\\\$/g;     # Backslash any $ in $r_con->{dirb}
    $tmp =~ s/$tmp2//g;       # Remove the directory portion
    $blist->{$tmp} = $mtime;
  };
  if ( -d $r_con->{dirb} ) {  find(\&$xxx,$r_con->{dirb});
  }else{
    croak "Invalid directory name for dirb ($r_con->{dirb})\n";
  }

  $r_con->{alist} = \$alist ;
  $r_con->{blist} = \$blist ;
  

  bless  $r_con, 'File::Repl';
  return $r_con;
}
#=====================================================================
sub Update {
  my($r_con,$regex,$mode,$commit) =@_;

# Valid entries for mode:
#     Only update files that exist on both source and target
# a>b   default action
# a<b
# a<>b
#     Force replication of all files - even if they don't exist on
#     target. (but don't overwrite newer files).
# A>B
# A<B
# A<>B

  $mode   = 'a>b' if ( $mode eq "" );      # Set the default operating mode
  $commit =  1 unless $commit; # Ser default commit value

  my($verbose) = $r_con->{verbose};
  my($name,$mtime,%mark,$afile,$bfile,$amtime,$bmtime,$fc,$md,$del);
  my(@amatch,@bmatch,@common,@aonly,@bonly);
  print "Update \n	Regex : $regex\n	Mode  : $mode\n	Commit: $commit\n\n" if ($verbose >= 2);

# Find files matching the regex in dira

  my($refa) = $r_con->{alist};
  
  print "Files Matching regex in $r_con->{dira}:\n" if ($verbose >= 2);
  foreach $name (keys %$$refa) {
    if ( $name =~ /$regex/ ) {
      $mtime = %$$refa->{$name};
      print "  $name	$mtime\n" if ($verbose >= 2);
      push (@amatch,$name);
    }
  }
# Find files matching the regex in dirb
  my($refb) = $r_con->{blist};
  print "Files Matching regex in $r_con->{dirb}:\n" if ($verbose >= 2);
  foreach $name (keys %$$refb) {
    if ( $name =~ /$regex/ ) {
      $mtime = %$$refb->{$name};
      print "  $name	$mtime\n" if ($verbose >= 2);
      push (@bmatch,$name);
    }
  }
# Find elements that are common/unique to @amatch and @bmatch
# -put in sorted order so that we can create directories/files
#  in one sweep (ie we don't try to create a file before its
#  parent directory exists)
  grep($mark{$_}++,@amatch);
  @common = sort(grep($mark{$_},@bmatch));   # Elements common to both @amatch and @bmatch
  undef %mark;
  grep($mark{$_}++,@bmatch);
  @aonly  = sort(grep(!$mark{$_},@amatch));  # Elements unique to @bmatch
  undef %mark;
  grep($mark{$_}++,@amatch);
  @bonly  = sort ( grep(!$mark{$_},@bmatch));# Elements unique to @bmatch
  undef %mark;

  if ( $verbose >= 3 ) {
    print "Common Files :\n";
    foreach (@common) {
      print "  $_\n";
    }
    print "A dir only Files :\n";
    foreach (@aonly) {
      print "  $_\n";
    }
    print "B dir only Files :\n";
    foreach (@bonly) {
      print "  $_\n";
    }
  }
  # sub to copy files and build directory dtructure
  $fc = sub {
    my($a,$b,$amtime) = @_;
    &$md(dirname($b)); # Make sure the parent of the target file exists
    if ( -f $a ) {
      copy ($a,$b) || warn "unable to copy $a\n";
      utime($amtime,$amtime,$b) || &gripe ( "Failed to set modification time on $b\n");
    }else{
      if ( ! -d $b ) {
        mkdir($b,0777) || warn "Unable to create directory $b\n";
      }
      utime($amtime,$amtime,$b) || &gripe ( "Failed to set modification time on $b\n");
    }
  };
  # sub to test a directory tree exists, and if not to create it
  $md = sub {
    my($Dir) = @_;
    return if (-d $Dir); # Quit if the directory exists
    $Dir =~ /(.*)\/([^\/]*)/;
    my($parent,$dir) = ($1,$2);
    &$md($parent) if (!-d $parent);  # Create the parent if it does not exist
    mkdir ($Dir, 0777) || warn "Unable to create directory $Dir\n";
  };
  $del = sub {
    my($targ) = @_;
    if (-d $targ) {
      print "  rmdir $targ\n" if ($verbose >= 1);
      if ($commit == 1) {
        rmdir $targ ||warn "Unable to delete directory $targ\n";
      }
    }elsif (-f $targ) {
      print "  rm $targ\n" if ($verbose >= 1);
      if ($commit == 1) {
        unlink $targ ||warn "Unable to delete file $targ\n";
      }
    }else{
    }
  };

  if ( $mode =~ /^(A>B)|(A<>B)$/ ) {
    foreach (@aonly) {
      $afile  = $r_con->{dira} . $_;
      $amtime = %$$refa->{$_};
      $bfile  = $r_con->{dirb} . $_;
      print "  $afile --> $bfile  \n" if ($verbose >= 1);
      if ($commit == 1) {
        if ( -d $afile) {
          mkdir($bfile,0777);
        }else{
          &$fc ($afile,$bfile,$amtime);
        }
      }
    }	
  }
  if ( $mode =~ /^(A<B)|(A<>B)$/ ) {
    foreach (@bonly) {
      $afile  = $r_con->{dira} . $_;
      $bfile  = $r_con->{dirb} . $_;
      $bmtime = %$$refb->{$_};
      print "  $afile <-- $bfile  \n" if ($verbose >= 1);
      if ($commit == 1) {
        if ( -d $bfile) {
          mkdir($afile,0777);
        }else{
          &$fc ($bfile,$afile,$bmtime);
        }
      }
    }	
  }
  if ( $mode =~ /^A<B!$/ ) {
    foreach (@aonly) {
      &$del( $r_con->{dira} . $_);
    }	
  }
  if ( $mode =~ /^A>B!$/ ) {
    foreach (@bonly) {
      &$del ($r_con->{dirb} . $_);
    }	
  }
  foreach (@common) {
    $amtime = %$$refa->{$_};
    $bmtime = %$$refb->{$_};
    $afile  = $r_con->{dira} . $_;
    $bfile  = $r_con->{dirb} . $_;
    if ( $amtime > $bmtime ) {
      if ( $mode =~ /^(a>b)|(a<>b)|(A>B)|(A>B!)|(A<>B)$/ ) {
        print " $afile --> $bfile  \n" if ($verbose >= 1);
        print " ($amtime) > ($bmtime)  \n" if ($verbose >= 1);
        if ($commit == 1) {
          &$fc ($afile,$bfile,$amtime);
        }
      }
    }elsif ( $amtime < $bmtime ) {
      if ( $mode =~ /^(a<b)|(a<>b)|(A<B)|(A<B!)|(A<>B)$/ ) {
        print " $afile <-- $bfile  \n" if ($verbose >= 1);
        if ($commit == 1) {
          &$fc ($bfile,$afile,$bmtime);
        }
      }
    }
  }
}


#=====================================================================

1;
__END__

=head1 NAME

File::Repl - Perl module that provides file replication utilities

=head1 SYNOPSIS

  use File::Repl;

  %con = (
     'dira',      'D:/perl',
     'dirb',      'M:/perl',
     'verbose',   '1',
     );

  $ref=File::Repl::SetDefaults(%con);
  $ref->Update('\.p(l|m)','a<>b',1);

=head1 DESCRIPTION

The File:Repl module provides a simple file replication utility. This
allows two directory structures to be maintained.

The Update routine has several arguments.  The first argument is a regular
expression, used to match all file names that to be maintained.  The second
argument defines the action to be performed.

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

=item A<B

Files in the 'b' directory are to be replicated to the 'a' directory
- even if no replica exists in 'a' directory.  If a replica already exists
in the 'a' directory with a timestamp that is newer than that of the file
in the 'b' directory it is not modified.

=item A<B!

Files in the 'b' directory are to be replicated to the 'a' directory
- even if no replica exists in 'a' directory.  If a replica already exists
in the 'a' directory with a timestamp that is newer than that of the file
in the 'b' directory it is not modified. Orphan files in the 'a'
directory are deleted. 

=item A<>B

Files in the 'a' directory are to be replicated to the 'b' directory
- even if no replica exists in 'b' directory.  If a replica already exists
in the 'b' directory with a timestamp that is newer than that of the file
in the 'a' directory it is not modified. Files in the 'b' directory are to 
be replicated to the 'a' directory - even if no replica exists in 'a' 
directory.  If a replica already exists in the 'a' directory with a 
timestamp that is newer than that of the file
in the 'b' directory it is not modified.

=back

The verbose flag has several valid values:

=over 4

=item 0

No verbosity (default mode)

=item 1

All file copies and deletes are printed.  

=item 2

Files identified in each directory that match the regex are printed.  SetDefault
parameters are also displayed, and the regex and commit parameters printed each
time the Update routine is called.

=item 3

Files with identical names in both directories are printed.  


=back

=head1 AUTHOR

Copyright E<#169> 2000 Dave Roberts, DaveRoberts@iname.com

This module is free software; you can redistribute it or modify it under the
same terms as Perl itself. 

=cut
