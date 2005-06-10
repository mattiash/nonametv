package NonameTV::Importer::CanalPlus;

use strict;
use warnings;

=pod

Importer for data from Canal+. 
One file per channel and week downloaded from their site.
The downloaded file is in xml-format.

Features:

=cut

use DateTime;
use XML::LibXML;

use NonameTV qw/MyGet Utf8Conv AddCategory/;

use NonameTV::Importer::BaseWeekly;

use base 'NonameTV::Importer::BaseWeekly';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

     $self->{grabber_name} = "CanalPlus";

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    return $self;
}

sub ImportContent
{
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my $l = $self->{logger};
  my $ds = $self->{datastore};

  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_string($$cref); };
  if( $@ ne "" )
  {
    $l->error( "$batch_id: Failed to parse" );
    return;
  }
  
  $ds->StartBatch( $batch_id );
  
  # Find all "Schedule"-entries.
  my $ns = $doc->find( "//Schedule" );
  
  foreach my $sc ($ns->get_nodelist)
  {
    # Sanity check. 
    # What does it mean if there are several programs?
    die "Wrong number of Programs for Schedule " .
      $sc->findvalue( '@Id' )
      if( $sc->findvalue( 'count(.//Program)' ) ) != 1;
    
    my $start = create_dt( $sc->findvalue( './@CalendarDate' ) );

    my $next_start = create_dt( $sc->findvalue( './@NextStart' ) );
    
    my $length  = $sc->findvalue( './Program/@Length ' );
    my $end = $start->clone()->add( minutes => $length );

    # Sometimes the claimed length of the movie makes the movie end
    # a few minutes after the next movie is supposed to start.
    # Assume that next_start is correct.
    if( $end > $next_start )
    {
      $end = $next_start;
    }
    
    my $title = $sc->findvalue( './Program/@Title' );
    my $desc  = $sc->findvalue( './Program/@LongSynopsis' );
    
    my $genre = norm($sc->findvalue( './Program/@Genre' ));
#    my $country = $sc->findvalue( './Program/@Country' );

    # LastChance is 0 or 1.
#    my $lastchance = $sc->findvalue( '/Program/@LastChance' );

    # PremiereDate can be compared with CalendarDate
    # to see if this is a premiere.
#    my $premieredate = $sc->findvalue( './Program/@PremiereDate' );

    # program_type can be partially derived from this:
    my $sport = $sc->findvalue( './Program/@Sport' );
    my $series = $sc->findvalue( './Program/@Series' );

    my $production_year = $sc->findvalue( './Program/@ProductionYear' );

    my $sixteen_nine = $sc->findvalue( './Program/@SixteenNine' );
#    my $letterbox = $sc->findvalue( './Program/@Letterbox' );
    
    # Finns även info om skådespelare och regissör på ett lättparsat format.

    my $ce = {
      channel_id  => $chd->{id},
      title       => norm($title),
      description => norm($desc),
      start_time  => $start->ymd("-") . " " . $start->hms(":"),
      end_time    => $end->ymd("-") . " " . $end->hms(":"),
      aspect      => $sixteen_nine ? "16:9" : "4:3", 
    };

    if( $series )
    {
      $ce->{program_type} = "series";
    }

    if( $sport )
    {
      $ce->{category} = 'Sports';
    }

    my($program_type, $category ) = $ds->LookupCat( "CanalPlus", 
                                                    $genre );
    AddCategory( $ce, $program_type, $category );

    if( defined( $production_year ) and ($production_year =~ /(\d\d\d\d)/) )
    {
      $ce->{production_date} = "$1-01-01";
    }

    $ds->AddProgramme( $ce );
  }
  
  $ds->EndBatch( 1 );
}

sub create_dt
{
  my( $str ) = @_;
  
  my( $date, $time ) = split( 'T', $str );

  my( $year, $month, $day ) = split( '-', $date );
  
  # Remove the dot and everything after it.
  $time =~ s/\..*$//;
  
  my( $hour, $minute, $second ) = split( ":", $time );
  
  
  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          second => $second,
                          time_zone => 'Europe/Stockholm',
                          );
  
  $dt->set_time_zone( "UTC" );
  
  return $dt;
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my( $year, $week ) = ($batch_id =~ /_(\d+)-(\d+)/);

  # Find the first day in the given week.
  # Copied from
  # http://www.nntp.perl.org/group/perl.datetime/5417?show_headers=1 
  my $dt = DateTime->new( year=>$year, day => 4 );
  $dt->add( days => $week * 7 - $dt->day_of_week - 6 );


  my $url = $self->{UrlRoot} .
    "d=" . $dt->ymd("-") . "\&c=$data->{grabber_info}";

  my( $content, $code ) = MyGet( $url );
  return( $content, $code );
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
