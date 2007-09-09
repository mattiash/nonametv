package NonameTV::Importer::Bleb;

use strict;
use warnings;

=pod

Importer for data from bleb.org.
The data are in XML format.

Features:

=cut

use DateTime;
use XML::LibXML;

use NonameTV qw/MyGet norm AddCategory/;
use NonameTV::Log qw/info progress error logdie/;

use NonameTV::Importer::BaseOne;

use base 'NonameTV::Importer::BaseOne';

my $strdmy;

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{grabber_name} = "Bleb";

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    return $self;
}

sub ImportContent
{
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;

  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_string($$cref); };
  if( $@ ne "" )
  {
    error( "$batch_id: Failed to parse $@" );
    return 0;
  }
  

  # Find all "channel"-entries.
  my $ch = $doc->find( "//channel" );

  foreach my $c ($ch->get_nodelist)
  {
    #
    # date
    #
    $strdmy = $c->findvalue( './@date' ) ;

  }


  # Find all "programme"-entries.
  my $ns = $doc->find( "//programme" );
  
  foreach my $sc ($ns->get_nodelist)
  {
    
    #
    # start time
    #
    my $starttime = $sc->getElementsByTagName('start');
    if( not defined $starttime )
    {
      error( "$batch_id: Invalid starttime '" . $sc->findvalue( './@start' ) . "'. Skipping." );
      next;
    }
    my $start = $self->create_dt( $starttime );

    #
    # end time
    #
    my $endtime = $sc->getElementsByTagName('end');
    if( not defined $endtime )
    {
      error( "$batch_id: Invalid endtime '" . $sc->findvalue( './@stop' ) . "'. Skipping." );
      next;
    }
    my $end = $self->create_dt( $endtime );

#print "$starttime -> $start\n";
#print "$endtime -> $end\n";
    
    #
    # check once more if start/end are extracted and defined ok
    #
    if( not defined $start or not defined $end )
    {
      error( "$batch_id: Invalid start/end times '" . $sc->findvalue( './@start' ) . "'. Skipping." );
      next;
    }

    #
    # title, subtitle
    #
    my $title = $sc->getElementsByTagName('title');
    my $subtitle = $sc->getElementsByTagName('subtitle');
#print "$title\n";
#print "$subtitle\n";
    
    #
    # description
    #
    my $desc  = $sc->getElementsByTagName('desc');
#print "$desc\n";
    
    #
    # url
    #
    my $url = $sc->getElementsByTagName( 'infourl' );
#print "$url\n";

    #
    # programme type
    #
    my $type = $sc->getElementsByTagName( 'type' );
#print "$type\n";

    #
    # production year
    #
    my $production_year = $sc->getElementsByTagName( 'year' );
#print "$production_year\n";

    my $ce = {
      channel_id   => $chd->{id},
      #title        => norm($title) || norm($subtitle),
      title        => norm($title),
      #subtitle     => norm($subtitle),
      description  => norm($desc),
      start_time   => $start->ymd("-") . " " . $start->hms(":"),
      end_time     => $end->ymd("-") . " " . $end->hms(":"),
      url          => norm($url),
    };

    my($program_type, $category ) = $ds->LookupCat( "Bleb", $type );
    AddCategory( $ce, $program_type, $category );
    
    if( defined( $production_year ) and ($production_year =~ /(\d\d\d\d)/) )
    {
      $ce->{production_date} = "$1-01-01";
    }

    $ds->AddProgramme( $ce );
  }
  
  # Success
  return 1;
}

sub create_dt
{
  my $self = shift;
  my( $strhour ) = @_;
  
#print "$strdmy\n";
#print "$strhour\n";

  if( length( $strhour ) == 0 )
  {
    return undef;
  }

  my $day = substr( $strdmy , 0 , 2 );
  my $month = substr( $strdmy , 3 , 2 );
  my $year = substr( $strdmy , 6 , 4 );

  my $hour = substr( $strhour , 0 , 2 );
  my $minute = substr( $strhour , 2 , 2 );
  my $second = 0;
  my $offset = 0;

  if( not defined $year )
  {
    return undef;
  }
  
  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          second => $second,
                          time_zone => 'Europe/London',
                          );
  
  $dt->set_time_zone( "UTC" );
  
  return $dt;
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my( $year, $week ) = ($batch_id =~ /_(\d+)-(\d+)/);

  # Bleb provides listings for today + 6 days
  # in different directory for every day
  # starting with 0 for today

  my $day = 2;
  my $url = $self->{UrlRoot} . "/" . $day . "/" . $data->{grabber_info};
print "URL: $url\n";

  my ( $content, $code ) = MyGet( $url );
  return( $content, $code );
}

1;
