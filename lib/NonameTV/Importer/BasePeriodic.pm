package NonameTV::Importer::BasePeriodic;

use strict;
use warnings;

=pod

Abstract base-class for an Importer that downloads data in one 
file for each period. 

Grabbers should normally derive from BaseOne, BaseWeekly or BaseDaily
instead. They all derive from BasePeriodic. To implement a grabber deriving
from BaseOne, BaseWeekly or BaseDaily, the following methods must be
implemented:

  my $error = $imp->InitiateDownload();


InitiateChannelDownload
Object2Url
FilterContent
ImportContent
 
=cut

use DateTime;
use POSIX qw/floor/;

use NonameTV qw/MyGet/;
use NonameTV::Log qw/info progress error logdie
                     log_to_string log_to_string_result/;
use NonameTV::ContentCache;

use NonameTV::Importer;

use base 'NonameTV::Importer';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{OptionSpec} = [ qw/force-update verbose+ short-grab/ ];
    $self->{OptionDefaults} = { 
      'force-update' => 0,
      'verbose'      => 0,
      'short-grab'   => 0,
    };

    # $self->{grabber_name} hasn't been set yet, so we'll build our
    # own name from the class name.
    my $name = ref( $self );
    $name =~ s/.*:://;

    $self->{cc} = NonameTV::ContentCache->new( { 
      basedir => "/var/local/nonametv/contentcache/" . 
          $name,
      callbackobject => $self,
      warnafter => 23*60*60,
      useragent => "Grabber from http://tv.swedb.se", 
    } );

    return $self;
}

sub BatchPeriods { 
  my $self = shift;
  my( $shortgrab ) = @_;

  die "You must override BatchPeriods";
}

sub InitiateDownload {
  my $self = shift;

  return undef;
}

sub InitiateChannelDownload {
  my $self = shift;
  my( $chd ) = @_;

  return undef;
}

sub ImportContent
{
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  die "You must override ImportContent";
}

sub Import {
  my $self = shift;
  my( $p ) = @_;
  
  if( not $self->can("Object2Url") ) {
    # Fallback to old code...
    return $self->ImportOld( $p );
  }

  NonameTV::Log::verbose( $p->{verbose} );

  my $error1 = $self->InitiateDownload();

  my $dsh = exists( $self->{datastorehelper} ) ? $self->{datastorehelper} : 
      $self->{datastore};

  my $ds = $self->{datastore};

  foreach my $data ($ds->FindGrabberChannels($self->{grabber_name}) ) {
    my $error2 = $self->InitiateChannelDownload( $data );

    if( $p->{'force-update'} and not $p->{'short-grab'} ) {
      if( defined( $error1 ) ) {
        error( $data->{xmltvid} . ": $error1\n" );
        next;
      }
  
      if( defined( $error2 ) ) {
        error( $data->{xmltvid} . ": $error2\n" );
        next;
      }

      # Delete all data for this channel.
      my $deleted = $ds->ClearChannel( $data->{id} );
      progress( "Deleted $deleted records for $data->{xmltvid}" );
    }

    my @batch_periods = $self->BatchPeriods( $p->{'short-grab'} );
 
    foreach my $period (@batch_periods) {
      my $batch_id = $data->{xmltvid} . "_" . $period;

      my( $cref, $error );
      if( defined( $error1 ) ) {
        $error = $self->{cc}->ReportError( $batch_id, $error1, 0 );
      }
      elsif( defined( $error2 ) ) {
        $error = $self->{cc}->ReportError( $batch_id, $error2, 0 );
      }
      else {
        info( "$batch_id: Fetching data" );
        ( $cref, $error ) = $self->{cc}->GetContent( 
          $batch_id, $data, $p->{'force-update'} );
      }

      if( defined $cref ) { 
        progress( "$batch_id: Processing data" );
        $dsh->StartBatch( $batch_id, $data->{id} );
        # Log ERROR and FATAL
        my $h = log_to_string( 4 );
        my $res = $self->ImportContent( $batch_id, $cref, $data );
        my $message = log_to_string_result( $h );
        $dsh->EndBatch( $res, $message );
      }
      elsif( defined $error ) {
        error( "$batch_id: $error" );
        $ds->SetBatchAbortMessage( $error );
      }
      else {
        # Nothing has changed.
      }
    }
  }
}

sub ImportOld {
  my $self = shift;
  my( $p ) = @_;

  NonameTV::Log::verbose( $p->{verbose} );

  my $ds = $self->{datastore};

  foreach my $data ($ds->FindGrabberChannels($self->{grabber_name}) ) {
    if( $p->{'force-update'} and not $p->{'short-grab'} ) {
      # Delete all data for this channel.
      my $deleted = $ds->ClearChannel( $data->{id} );
      progress( "Deleted $deleted records for $data->{xmltvid}" );
    }

    my @batch_periods = $self->BatchPeriods( $p->{'short-grab'} );
 
    foreach my $period (@batch_periods) {
      my $batch_id = $data->{xmltvid} . "_" . $period;

      $self->ImportBatch( $batch_id, $data, $p->{'force-update'} );
    }
  }
}

=pod

ImportBatch

Called from Base*.pm to import data for a single batch. Logs errors to the 
batch-entry in the database.

=cut

sub ImportBatch {
  my $self = shift;

  my( $batch_id, $chd, $force_update ) = @_;

  my $ds;

  # Log ERROR and FATAL
  my $h = log_to_string( 4 );

  info( "$batch_id: Fetching data" );
  
  if( exists( $self->{datastorehelper} ) ) {
    $ds = $self->{datastorehelper};
  }
  else {
    $ds = $self->{datastore};
  }

  $ds->StartBatch( $batch_id, $chd->{id} );

  my( $content, $code ) = $self->FetchData( $batch_id, $chd );
  
  if( not defined( $content ) ) {
    error( "$batch_id: Failed to fetch data ($code)" );
    my $message = log_to_string_result( $h );
    $ds->EndBatch( 0, $message );
    return;
  }
  elsif( (not ($force_update) and ( not $code ) ) ) {
    # No changes.
    $ds->EndBatch( -1 );
    return;
  }

  progress( "$batch_id: Processing data" );

  my $res = $self->ImportContent( $batch_id, \$content, $chd ); 

  my $message = log_to_string_result( $h );

  if( $res ) {
    # success
    $ds->EndBatch( 1, $message );
  }
  else {
    # failure
    $ds->EndBatch( 0, $message );
  }
}


sub FetchData {
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my $root = "/var/local/nonametv/override";
  my $code = 0;
  my $content;

  if( -f( "$root/new/$batch_id" ) ) {
    move( "$root/new/$batch_id", "$root/data/$batch_id" );
    $code = 1;
  }

  if( -f( "$root/data/$batch_id" ) ) {
    # Check if the data on site has changed
    my( $site_content, $site_code ) = 
      $self->FetchDataFromSite( $batch_id, $data );

    print STDERR "$batch_id New data available for override.\n"
      if( $site_code );
    
    $site_content = undef;

    # Load data from file
    {
      local( $/ ) ;
      open( my $fh, "$root/data/$batch_id" ) 
        or die "Failed to read form $root/data/$batch_id: $@";
      $content = <$fh>;
    }
  }
  else {
    ( $content, $code ) = $self->FetchDataFromSite( $batch_id, $data );
    if( -f( "$root/delete/$batch_id" ) ) {
      # Delete the old override and force update from site.
      unlink( "$root/delete/$batch_id" );
      $code = 1;
    }
  }
  
  return ($content, $code);
}


1;
