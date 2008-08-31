package NonameTV::Log;

=pod

Logging-module for NonameTV.

=head2 USAGE

The logging functions all take a string as argument. This string is
prefixed with the chosen severity and current context and appended to
the different logging outputs that are available.

The following logging functions are available:

 d Debug
 p Progress
 w Warning. Execution of this task continued anyway. 
 f Fatal error. Execution of this task will be aborted.

For example:

  if( $errorcondition ) {
    w "Something wrong";
  }

  if( $downloadfailed ) {
    f "Download failed";
    return 0;
  }


=head3 LogSection

StartLogSection/EndLogSection can be used to catch all warnings and
fatal errors in a section of code. This is for example used to catch
log messages emitted for each batch in an importer.

 
  StartLogSection( "batchname" );
    (do stuff that may emit log messages)
  my( $messages, $highestpriority ) = EndLogSection( "batchname" );


StartLogSection can be nested. An outer LogSection will NOT catch
messages that are caught by the inner LogSection.

=head2 LOGGING OUTPUTS

STDERR

Each message is prefixed with the severity and the current LogSection
name.

Normally, severities Warning and Fatal are printed.

--verbose prints Progress as well.
--verbose=2 prints Debug and Progress as well.
--quiet prints only Fatal.
--quiet=2 prints nothing

LOGFILE

LogFile logs everything up to and including severity Progress. Each
message is prefixed with the severity and the current LogSection name.

LOGSECTION

EndLogSection returns all messages with priority warning and fatal
that have been issued since the matching call to StartLogSection. The
messages are prefixed with the severity.

Compatibility functions

LogSection is not appended to these strings.

=cut

use strict;
use warnings;

use POSIX qw/strftime/;
use IO::File;

use Carp qw/confess/;

use NonameTV::Config qw/ReadConfig/;

BEGIN 
{
  use Exporter   ();
  our (@ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
  
  @ISA         = qw(Exporter);
  @EXPORT      = qw( );
  %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
  @EXPORT_OK   = qw/progress error
                    d p w f
                    StartLogSection EndLogSection
                    SetVerbosity/;
  
}
our @EXPORT_OK;

sub d;
sub p;
sub w;
sub e;

use constant {
  DEBUG => 1,
  PROGRESS => 2,
  WARNING => 3,
  FATAL => 4,
  NONE => 100,
};

my $stderr_level = WARNING;
my $file_level = PROGRESS;


my $logfile;
my @section = [ undef, "" ];

BEGIN {
  my $conf = ReadConfig();

  $logfile = new IO::File "$conf->{LogFile}", O_WRONLY|O_APPEND|O_CREAT;

  die "Failed to open logfile $conf->{LogFile} for writing"
    unless defined $logfile;

  # Flush the logfile to disk for each write.
  $logfile->autoflush( 1 );

  # Turn all "warn" statements into w():s.
  $SIG{'__WARN__'} = \&w;
}

sub SetVerbosity {
  my( $verbose, $quiet ) = @_;

  if( $verbose == 1 ) {
    $stderr_level = PROGRESS;
  }
  elsif( $verbose > 1 ) {
    $stderr_level = DEBUG;
  }
  elsif( $quiet == 1 ) {
    $stderr_level = FATAL;
  }
  elsif( $quiet > 1 ) {
    $stderr_level = NONE;
  }
  else {
    $stderr_level = WARNING;
  }
}

sub d {
  my( $message ) = @_;

  writelog( DEBUG, "D", $section[0][0], $message );
}

sub p {
  my( $message ) = @_;

  writelog( PROGRESS, "P", $section[0][0], $message );
}

sub w {
  my( $message ) = @_;

  writelog( WARNING, "W", $section[0][0], $message );
}

sub f {
  my( $message ) = @_;

  writelog( FATAL, "F", $section[0][0], $message );
}

sub writelog {
  my( $level, $levelstr, $prefix, $message ) = @_;

  # Remove trailing newline added by warn.
  $message =~ s/\s+$//;

  my $pmessage;
  if( defined( $prefix ) ) {
    $pmessage = "$prefix: $message";
  }
  else {
    $pmessage = $message;
  }

  my $time = strftime( '%F %T', localtime );

  if( $level >= $stderr_level ) {
    print STDERR "$levelstr: $pmessage\n";
  }

  if( $level >= $file_level ) {
    print $logfile "$time $levelstr: $pmessage\n";
  }

  if( $level >= WARNING ) {
    $section[0][1] .= "$levelstr: $message\n";
  }
}

sub StartLogSection {
  my( $sectionname ) = @_;

  unshift @section, [ $sectionname, "" ];
}

sub EndLogSection {
  my( $sectionname ) = @_;

  if( $sectionname eq $section[0][0] ) {
    my $result = $section[0][1];
    shift @section;
    return $result;
  }
  else { 
    confess "Mismatched LogSections, got $sectionname, expected $section[0][0]";
  }
}

# Deprecated functions
sub progress {
  my( $message ) = @_;

  writelog( PROGRESS, "PROG", undef, $message );
}

sub error {
  my( $message ) = @_;

  writelog( WARNING, "ERROR", undef, $message );
}


1;
