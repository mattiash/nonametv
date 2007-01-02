package NonameTV::Importer::Eurosport;

use strict;
use warnings;

=pod

Import data from xml-files that we download via FTP. Use BaseFile as
ancestor to avoid redownloading and reprocessing the files each time.

=cut

use utf8;

use DateTime;
use XML::LibXML;

use NonameTV qw/MyGet norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/info progress error logdie 
                     log_to_string log_to_string_result/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  $self->{grabber_name} = "Eurosport";

  defined( $self->{FtpRoot} ) or die "You must specify FtpRoot";
  defined( $self->{Filename} ) or die "You must specify Filename";

  return $self;
}

sub ImportContentFile
{
  my $self = shift;
  my( $file, $chd ) = @_;

  progress( "Eurosport: Processing $file" );
  
  $self->{fileerror} = 0;

  my $xmltvid=$chd->{xmltvid};

  my $channel_id = $chd->{id};
  my $ds = $self->{datastore};

  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_file($file); };
  
  if( not defined( $doc ) ) {
    error( "Eurosport $file: Failed to parse" );
    return;
  }
  
  # Find all paragraphs.
  my $ns = $doc->find( "//BroadcastDate_GMT" );
  
  if( $ns->size() == 0 ) {
    error( "Eurosport $file: No BroadcastDates found." ) ;
    return;
  }

  foreach my $sched_date ($ns->get_nodelist) {
    my( $date ) = norm( $sched_date->findvalue( '@Day' ) );
    my $dt = create_dt( $date );

    my $batch_id = $xmltvid . "_" . $dt->ymd('-');
    $ds->StartBatch( $batch_id );
    
    my $ns2 = $sched_date->find('Emission');
    foreach my $emission ($ns2->get_nodelist) {
      my $start_time = $emission->findvalue( 'StartTimeGMT' );
      my $end_time = $emission->findvalue( 'EndTimeGMT' );

      my $start_dt = create_time( $dt, $start_time );
      my $end_dt = create_time( $dt, $end_time );

      if( $end_dt < $start_dt ) {
        $end_dt->add( days => 1 );
      }

      my $title = norm( $emission->findvalue( 'Title' ) );
      my $desc = norm( $emission->findvalue( 'Feature' ) );

      my $ce = {
        channel_id => $channel_id,
        start_time => $start_dt->ymd('-') . ' ' . $start_dt->hms(':'),
        end_time   => $end_dt->ymd('-') . ' ' . $end_dt->hms(':'),
        title => $title,
        description => $desc,
      };

      $ds->AddProgramme( $ce );
      
    }
    $ds->EndBatch( 1 );
  }

  return;
}

sub UpdateFiles {
  my( $self ) = @_;

  my $sth = $self->{datastore}->Iterate( 'channels', 
     { grabber => $self->{grabber_name} } )
    or logdie( "$self->{grabber_name}: Failed to fetch grabber data" );

  while( my $data = $sth->fetchrow_hashref ) {
    
    my $dir = $data->{grabber_info};
    my $xmltvid = $data->{xmltvid};

    ftp_get( $self->{FtpRoot} . $dir . '/' . $self->{Filename},
             $NonameTV::Conf->{FileStore} . '/' . 
             $xmltvid . '/' . $self->{Filename} );
  }  

  $sth->finish();
}

sub ftp_get {
  my( $url, $file ) = @_;

  qx[curl -s -S -z $file -o $file $url];
}

sub create_dt {
  my( $text ) = @_;

  my($day, $month, $year ) = split( "/", $text );

  return DateTime->new( year => $year,
                        month => $month,
                        day => $day,
                        time_zone => "GMT" );
}

sub create_time {
  my( $dt, $time ) = @_;

  my $result = $dt->clone();

  my( $hour, $minute ) = split(':', $time );

  $result->set( hour => $hour,
                minute => $minute,
                );

  return $result;
}
1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
