package NonameTV::Importer::Svt;

use strict;
use warnings;

use DateTime;
use XML::LibXML;
use Text::Iconv;
use IO::Wrap;

use NonameTV::Importer;

use base 'NonameTV::Importer';

our $OptionSpec = [ qw/force-update/ ];
our %OptionDefaults = ( 
                        'force-update' => 0,
                        );

my $conv = Text::Iconv->new("UTF-8", "ISO-8859-1" );

my %channel_ids;

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    return $self;
}

sub Import
{
  my $self = shift;
  my( $ds, $cache, $p ) = @_;
  
  my $xml = XML::LibXML->new;
  my $doc = $xml->parse_fh( wraphandle( \*STDIN ) );

  # channel, week kan användas som batch_name.
  # week går efter date_schedule.
  # Varje xml-fil innehåller flera veckors data,
  # men bör behandlas som flera batchar eftersom
  # det kanske kan komma en fil per vecka som 
  # innehåller data för ett antal veckor framåt.

  # The input must be sorted in <channel> and <week> order!
  my $ns = $doc->find( "//program" );

  my $batch = "";
  
  foreach my $p ($ns->get_nodelist)
  {
    my $week = $p->findvalue('week_number/text()');
    my $channel = $p->findvalue('channel');
    my $channel_id = get_channel_id( $ds, $channel );
    my $channel_xmltvid = get_channel_xmltvid( $ds, $channel );


    my $currbatch = $channel_xmltvid . "_" . $week;
    
    if( $currbatch ne $batch )
    {
      if( $batch ne "" )
      {
        $ds->EndBatch(1);
      }

      $batch = $currbatch;
      $ds->StartBatch( $batch );
    }

    my $title = $p->findvalue('title/text()');
    my $start_date = $p->findvalue( 'date_utc/text()' );
    my $start_time = $p->findvalue( 'start_time_utc/text()' );
    my $length_min = $p->findvalue( 'length_minutes/text()' );

    my $description = $p->findvalue( 'long_description_complete/text()' );

    my $start = create_dt( $start_date, $start_time );
    my $end = $start->clone()->add( minutes => $length_min );

    $ds->AddProgramme( {
      channel_id  => $channel_id,
      title       => norm($title),
      description => norm($description),
      start_time  => $start->ymd("-") . " " . $start->hms(":"),
      end_time    => $end->ymd("-") . " " . $end->hms(":"),
    } );            
  }

  if( $batch ne "" )
  {
    $ds->EndBatch(1);
  }
}

sub get_channel_id
{
  my( $ds, $channel_name ) = @_;

  if( not exists( $channel_ids{$channel_name} ) )
  {
    $channel_ids{$channel_name} = 
      $ds->Lookup( 'channels',
                   { grabber => 'Svt',
                     grabber_info => $channel_name,
                   } );
  }

  return $channel_ids{$channel_name}->{id};
}

sub get_channel_xmltvid
{
  my( $ds, $channel_name ) = @_;

  if( not exists( $channel_ids{$channel_name} ) )
  {
    get_channel_id( $ds, $channel_name );
  }

  return $channel_ids{$channel_name}->{xmltvid};
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

    $str = $conv->convert( $str );

    $str =~ s/^\s+//;
    $str =~ s/\s+$//;

    $str =~ tr/\n\r\t /    /s;

    return $str;
}

1;
