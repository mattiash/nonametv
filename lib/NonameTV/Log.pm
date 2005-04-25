package NonameTV::Log;

=pod

Logging-module for NonameTV.

In each module, do

  use NonameTV::Log qw/get_logger start_output/;

  my $l=get_logger(__PACKAGE__);
  $l->info( "Fetching data" ); or warn, error, fatal, debug

  do_stuff() or $l->logdie "Failed to do stuff.";

Call start_output once for each invocation of a nonametv-* command. 
This is typically done in the Importer or Exporter-module.

  start_output( __PACKAGE__, $p->{verbose} );

Levels:

DEBUG Debugging output

INFO Progress messages

WARN Something has been updated in the database/external files.

ERROR Parse errors etc.

FATAL ??

Normal output consists of ERROR and FATAL only.

--verbose prints everything up to and including INFO for this logger.

/var/log/nonametv logs everything up to and including WARN

DEBUG-messages can be shown with per-logger options somehow...

=cut

use strict;
use warnings;

use Log::Log4perl qw/:levels/;

BEGIN 
{
  use Exporter   ();
  our (@ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
  
  @ISA         = qw(Exporter);
  @EXPORT      = qw( );
  %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
  @EXPORT_OK   = qw/start_output get_logger/;
  
  #
  # Log WARN, ERROR and FATAL to a file with timestamps.
  #
  my $deflog = Log::Log4perl::get_logger("NonameTV");
    
  my $appender = Log::Log4perl::Appender->new(
                                              "Log::Dispatch::File",
                                              filename => "/tmp/nonametv.log",
                                              mode => "append",
                                            );
  $appender->threshold( $WARN );

  my $layout = Log::Log4perl::Layout::PatternLayout->new( 
     '%d{yyyy-MM-dd HH:mm:ss} %1p %m%n' );

  $appender->layout( $layout );
  $deflog->add_appender( $appender );

  #
  # Log ERROR and FATAL to STDOUT
  #
  $appender = Log::Log4perl::Appender->new(
                                              "Log::Dispatch::Screen",
                                              );
  
  $appender->threshold( $ERROR );
  $layout = Log::Log4perl::Layout::PatternLayout->new( 
     '%1p %m%n' );
  $appender->layout( $layout );
  $deflog->add_appender( $appender );

}
our @EXPORT_OK;

sub start_output
{
  my( $package, $verbose ) = @_;

  #
  # Log WARN and INFO for the specified log-package to STDOUT if $verbose
  # is true. Note that ERROR and FATAL are not logged here, since
  # they are logged by the NonameTV-logger.
  #
  if( $verbose )
  {
    my $deflog = Log::Log4perl::get_logger($package);
    
    my $appender = Log::Log4perl::Appender->new(
                                                "Log::Dispatch::Screen",
                                                );
    
    my $filter = Log::Log4perl::Filter->new( "NonameTV::Filter",
        sub { my %p = @_; 
              return ($p{log4p_level} eq "WARN" or $p{log4p_level} eq "INFO");
            } );
    $appender->filter( $filter );

    my $layout = Log::Log4perl::Layout::PatternLayout->new( 
         '%1p %m%n' );
    $appender->layout( $layout );
    $deflog->add_appender( $appender );
  }
}

sub get_logger
{
  Log::Log4perl::get_logger( @_ );
}
