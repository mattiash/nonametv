package NonameTV::Importer::Svt_xml;

#
# Import data from the xml-files delivered via mail.
# Each file contains data for one channel for a period of
# a few weeks. The data is NOT sorted by the start-time.
#
# Episode-information is extracted from the descriptions.
#

use strict;
use warnings;

use DateTime;
use XML::LibXML;
use XML::LibXSLT;

use IO::Wrap;

use NonameTV::Importer;
use NonameTV qw/Utf8Conv/;

use base 'NonameTV::Importer';

our $OptionSpec = [ qw/force-update verbose/ ];
our %OptionDefaults = ( 
                        'force-update' => 0,
                        verbose        => 0,
                        );

sub new 
{
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);
  
  my $sth = $self->{datastore}->Iterate( 'channels', 
                                         { grabber => 'Svt' },
                                         qw/xmltvid id grabber_info/ )
    or die "Failed to fetch grabber data";
  
  while( my $data = $sth->fetchrow_hashref )
  {
    $self->{channel_data}->{$data->{grabber_info}} = 
      { 
        id => $data->{id},
        xmltvid => $data->{xmltvid},
      };
  }

  $sth->finish;
  
  return $self;
}


sub Import
{
  my $self = shift;
  my( $p ) = @_;

  foreach my $file (@ARGV)
  {
    $self->ImportFile( "", $file, $p );
  } 
}

sub ImportFile
{
  my $self = shift;
  my( $contentname, $file, $p ) = @_;

  print "Processing $file.\n"
    if( $p->{verbose} );

  my $ds = $self->{datastore};
  my $chd = $self->{channel_data};

  my $dt = DateTime->today->set_time_zone( 'Europe/Stockholm' );
  
  my( $content, $code );
  my $days = 0;

  my $parser = XML::LibXML->new();
  my $xslt = XML::LibXSLT->new();

  my $style_doc = $parser->parse_string(<<'EOXSLT');
<?xml version="1.0"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
               xmlns:exsl="http://exslt.org/common"
               extension-element-prefixes="exsl"
               version="1.0">

<xsl:template match="/">
  <programs>
    <xsl:for-each select="//program">
      <xsl:sort select="date_utc/text()"/>
      <xsl:sort select="start_time_utc/text()"/>
      <xsl:copy-of select="."/>
    </xsl:for-each>
  </programs>
</xsl:template>

</xsl:stylesheet>

EOXSLT

  my $stylesheet = $xslt->parse_stylesheet($style_doc);

  my $source;
  eval { $source = $parser->parse_file( $file ); };
  if( $@ ne "" )
  {
    print STDERR "$file Failed to parse\n";
    return;
  }
  
  my $doc = $stylesheet->transform($source);

  my $channel;
  my $channel_id;
  my $channel_xmltvid;

  my $sched_date = "nonametv-nodate";

  my $ns = $doc->find( "//program" );

  if( $ns->size() == 0 )
  {
    print STDERR "$file: No data found.\n";
    return;
  }
  
  foreach my $p ($ns->get_nodelist)
  {
    my $curr_channel = $p->findvalue( 'channel/text()' );

    if( not defined( $channel ) )
    {
      $channel = $curr_channel;
      if( not defined( $chd->{$channel} ) )
      {
        print STDERR "$file: Unknown channel $channel\n";
        return;
      }
   
      $channel_id = $chd->{$channel}->{id};
      $channel_xmltvid = $chd->{$channel}->{xmltvid};
    }

    if( $channel ne $curr_channel )
    {
      print STDERR "$file: Multiple channels in file, '$channel' and $curr_channel'\n";
      print STDERR "$file: Aborting.";
      $ds->EndBatch(0);
    }
    
    if( $sched_date ne $p->findvalue( 'date_schedule/text()' ) )
    {
      $ds->EndBatch( 1 ) 
        unless $sched_date eq 'nonametv-nodate';

      $sched_date = $p->findvalue( 'date_schedule/text()' );
      $ds->StartBatch( $channel_xmltvid . "_" . $sched_date );
      print "  $sched_date\n";
    }

    my $title = $p->findvalue('title/text()');
    my $start_date = $p->findvalue( 'date_utc/text()' );
    my $start_time = $p->findvalue( 'start_time_utc/text()' );
    my $length_min = $p->findvalue( 'length_minutes/text()' );
    
    my $description = $p->findvalue( 'long_description_complete/text()' );
    
    my $start = create_dt( $start_date, $start_time );
    my $end = $start->clone()->add( minutes => $length_min );
    
    my $ce = {
      channel_id  => $channel_id,
      title       => norm($title),
      description => norm($description),
      start_time  => $start->ymd("-") . " " . $start->hms(":"),
      end_time    => $end->ymd("-") . " " . $end->hms(":"),
    };

    extract_extra_info( $ce );

    $ds->AddProgramme( $ce );
  }
  
  $ds->EndBatch(1);
}


sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my( $xmltvid, $date ) = ($batch_id =~ /(.+)_(.+)/);

  my $url = $self->{UrlRoot} . $data->{grabber_info} . "_$date.xml";

  my( $content, $code ) = MyGet( $url );
  return( $content, $code );
}

sub extract_extra_info
{
  my( $ce ) = shift;

  return if not defined( $ce->{description} );

  my $d = $ce->{description};

  # Try to extract episode-information from the description.
  my( $ep, $eps );
  my $episode;

  # Del 2
  ( $ep ) = ($d =~ /\bDel\s+(\d+)/ );
  $episode = sprintf( " . %d .", $ep-1 ) if defined $ep;

  # Del 2 av 3
  ( $ep, $eps ) = ($d =~ /\bDel\s+(\d+)\s*av\s*(\d+)/ );
  $episode = sprintf( " . %d/%d . ", $ep-1, $eps ) 
    if defined $eps;
  
  $ce->{episode} = $episode if defined $episode;

}

sub create_dt
{
  my( $date, $time ) = @_;
  
  my( $year, $month, $day ) = split( '-', $date );
  
  my( $hour, $minute, $second ) = split( ":", $time );
  
  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          second => $second,
                          time_zone => 'UTC',
                          );
  
  return $dt;
}

# Delete leading and trailing space from a string.
# Convert all whitespace to spaces. Convert multiple
# spaces to a single space.
sub norm
{
    my( $str ) = @_;

    return "" if not defined( $str );

    $str = Utf8Conv( $str );

    $str =~ s/^\s+//;
    $str =~ s/\s+$//;

    $str =~ tr/\n\r\t /    /s;

    return $str;
}

1;
