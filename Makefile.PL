# File::Repl
#
# Version
#      $Source: D:/src/perl/File/Repl/RCS/Makefile.PL $
#      $Revision: 1.3 $
#      $State: Exp $
#
# Start comments/code here - will not be processed into manual pages
#
#    Copyright © Dave Roberts  2000,2001
#
# Revision history:
#      $Log: Makefile.PL $
#      Revision 1.3  2001/06/27 12:33:57  jj768
#      Changes to ignore the RCS directory
#
#
#******************************************************************************

use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'		=> 'File::Repl',
    'VERSION_FROM'	=> 'Repl.pm', # finds $VERSION
	($] ge '5.005')
	? (
		'AUTHOR' => 'Dave Roberts (robertsdavea@googlemail.com)',
		'ABSTRACT' => 'module that provides file replication utilities',
	)
	: (), 
);

package MY;

sub postamble {
    <<"END_OF_POSTAMBLE";

pm_to_blib: README

README: Repl.pm
\tpod2text Repl.pm >README
\tpod2html Repl.pm >Repl.html
END_OF_POSTAMBLE
}

# Just to make it ignore editor backup files.
sub libscan {
 	$_ = $_[1];
	if ( m/(RCS|CVS|SCCS)/i || m/[~%]$/ || m/\.(orig|rej)$/ ) {
	  print " Ignoring $_\n";
	  return '';
  }
  return $_;
}

