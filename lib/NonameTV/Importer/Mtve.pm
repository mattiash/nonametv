package NonameTV::Importer::Mtve;

#
# This importer imports data from MTV Europe's press service. 
#
# One xml-file per day. Each entry contains a start-time with a timezone,
# (CET), title, description, url and image for the show.
#

use strict;
use warnings;

use DateTime;
use XML::LibXML;

use NonameTV qw/MyGet Utf8Conv/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{grabber_name} = "Mtve";

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    return $self;
}

sub ImportContent
{
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $l = $self->{logger};
  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  my( $date ) = ($batch_id =~ /_(.*)$/);

  # Add a proper entity set reference to allow &Aring; etc.
  $$cref =~ s(\?>)(?><!DOCTYPE MTV [
<!ENTITY \% ISOlat1 PUBLIC "ISO 8879:1986//ENTITIES Added Latin 1//EN"
    "http://www.w3.org/2003/entities/iso8879/isolat1.ent">
\%ISOlat1; ]>);

  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_string($$cref); };
  if( $@ ne "" )
  {
    $l->error( "$batch_id: Failed to parse" );
    return;
  }
  
  # Verify the assumption that each file only contains data for
  # one channel.
  
  my $channelname = $doc->findvalue( '//Channel/@name' );
  if( $channelname ne $chd->{grabber_info} )
  {
    $l->error( "$batch_id: Wrong channel found: $channelname" );
#          next;
  }
  
  # Find all "ShowItem"-entries.
  my $ns = $doc->find( "//ShowItem" );
  if( $ns->size() == 0 )
  {
    $l->error( "$batch_id: No data found" );
    return;
  }
  
  $ds->StartBatch( $batch_id );
  
  foreach my $pgm ($ns->get_nodelist)
  {
    my $starttime = $pgm->findvalue( 'ShowDate' );
    
    my $start_dt = create_dt( $starttime );
    
    my $title =$pgm->findvalue( 'ShowName' );
    my $desc = $pgm->findvalue( 'ShowText' );
    
# Should we store url and image in the database?
#          my $url = $pgm->findvalue( 'ShowUrl' );
#          $url = URI->new($url)->abs('http://www.mtve.com/')
#            if defined($url);
    
#          my image = $pgm->findvalue( 'ShowImage' );
#          $image = URI->new($image)->abs('http://www.mtve.com/')
#            if defined($image);
    
    my $ce = 
    {
      channel_id  => $chd->{id},
      title       => norm($title),
      description => norm($desc),
      start_time  => $start_dt->ymd('-') . " " . 
        $start_dt->hms(":"),
      };
    
    $ds->AddProgramme( $ce );
  }
  
  $ds->EndBatch( 1 );
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my( $date ) = ($batch_id =~ /_(.*)/);

  my $url = $self->{UrlRoot} . $date;

  my( $content, $code ) = MyGet( $url );
  return( $content, $code );
}

sub create_dt
{
  my( $datetime ) = @_;

  my( $date, $time, $timezone ) = split( /\s+/, $datetime );

  die( "Mtve: Unknown timezone $timezone" ) 
    unless $timezone eq "CET";

  my( $year, $month, $day ) = split( "-", $date );
  my( $hour, $minute ) = split( ":", $time );
  
  my $dt = DateTime->new( 
                          year => $year,
                          month => $month, 
                          day => $day,
                          hour => $hour,
                          minute => $minute,
                          time_zone => "Europe/Stockholm" 
                          );
  
  $dt->set_time_zone( "UTC" );
  
  return $dt;
}

# Delete leading and trailing space from a string.
# Convert all whitespace to spaces. Convert multiple
# spaces to a single space.
sub norm
{
    my( $instr ) = @_;

    return "" if not defined( $instr );

    my $str = Utf8Conv( $instr );

    $str =~ s/^\s+//;
    $str =~ s/\s+$//;

    $str =~ tr/\n\r\t /    /s;

    return $str;
}

1;
