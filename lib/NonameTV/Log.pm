package NonameTV::Log;

=pod

Logging-module for NonameTV.

In each module, do

  use NonameTV::Log qw/info progress error logdie/;

  info( "Fetching data" ); or progress, error, fatal, debug

  do_stuff() or logdie "Failed to do stuff.";

Levels:

DEBUG Debugging output

INFO Progress messages

PROGRESS Something has been updated in the database/external files.

ERROR Parse errors etc.

FATAL Fatal error. Program terminated.

Normal output consists of ERROR and FATAL only.

--verbose prints everything up to and including INFO.

/var/log/nonametv logs everything up to and including PROGRESS

=cut

use strict;
use warnings;

use POSIX qw/strftime/;
use IO::File;

use Carp qw/confess/;

BEGIN 
{
  use Exporter   ();
  our (@ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
  
  @ISA         = qw(Exporter);
  @EXPORT      = qw( );
  %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
  @EXPORT_OK   = qw/init verbose
                    debug info progress error logdie
                    log_to_string log_to_string_result/;
  
}
our @EXPORT_OK;

use constant {
  DEBUG => 1,
  INFO => 2,
  PROGRESS => 3,
  ERROR => 4,
  FATAL => 5,
  NONE => 100 
};

my %levels = (
  (DEBUG) => "DEBUG",
  (INFO) => "INFO",
  (PROGRESS) => "PROG",
  (ERROR) => "ERROR",
  (FATAL) => "FATAL",
);

my $stderr_level;
my $file_level;
my $string_level;

my $logfile;
my $logstring;

sub init
{
  my( $conf ) = @_;

  $stderr_level = ERROR;
  $file_level = PROGRESS;
  $string_level = NONE;
  
  $logfile = new IO::File "$conf->{LogFile}", O_WRONLY|O_APPEND|O_CREAT;

  die "Failed to open logfile $conf->{LogFile} for writing"
    unless defined $logfile;

  # Flush the logfile to disk for each write.
  $logfile->autoflush( 1 );
}

sub verbose
{
  my( $verbose ) = @_;

  if( $verbose == 0 )
  {
    $stderr_level = ERROR;
  }
  elsif( $verbose == 1 )
  {
    $stderr_level = PROGRESS;
  }
  else
  {
    $stderr_level = INFO;
  }
}
 
sub log_to_string
{
  my( $level ) = @_;

  $string_level = $level;
  $logstring = "";
  return 123;
}

sub log_to_string_result
{
  my( $h ) = @_;

  $string_level = NONE;
  return $logstring;
}

sub info
{
  my( $message ) = @_;

  writelog( INFO, $message );
}

sub progress
{
  my( $message ) = @_;

  writelog( PROGRESS, $message );
}

sub error
{
  my( $message ) = @_;

  writelog( ERROR, $message );
}

sub logdie
{
  my( $message ) = @_;

  writelog( FATAL, $message );
  confess( $message );
}

sub writelog
{
  my( $level, $message ) = @_;

  my $time = strftime( '%F %T', localtime );

  my $levelstr = $levels{$level};
  
  if( $level >= $stderr_level )
  {
    print STDERR "$levelstr: $message\n";
  }

  if( $level >= $file_level )
  {
    print $logfile "$time $levelstr: $message\n";
  }

  if( $level >= $string_level )
  {
    $logstring .= "$levelstr: $message\n";
  }
}

1;
