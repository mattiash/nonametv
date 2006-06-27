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

use NonameTV qw/MyGet norm AddCategory/;
use NonameTV::Log qw/info progress error logdie/;

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

  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;
  $ds->{SILENCE_DUPLICATE_SKIP}=1;
 
  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_string($$cref); };
  if( $@ ne "" )
  {
    error( "$batch_id: Failed to parse $@" );
    return 0;
  }
  
  # Find all "Schedule"-entries.
  my $ns = $doc->find( "//Schedule" );
  
  foreach my $sc ($ns->get_nodelist)
  {
    # Sanity check. 
    # What does it mean if there are several programs?
    logdie "Wrong number of Programs for Schedule " .
      $sc->findvalue( '@Id' )
      if( $sc->findvalue( 'count(.//Program)' ) ) != 1;
    
    my $start = $self->create_dt( $sc->findvalue( './@CalendarDate' ) );
    if( not defined $start )
    {
      error( "$batch_id: Invalid starttime '" 
             . $sc->findvalue( './@CalendarDate' ) . "'. Skipping." );
      next;
    }

    my $next_start = $self->create_dt( $sc->findvalue( './@NextStart' ) );

    # NextStart is sometimes off by one day.
    if( defined( $next_start ) and $next_start < $start )
    {
      $next_start = $next_start->add( days => 1 );
    }

    my $length  = $sc->findvalue( './Program/@Length ' );
    die if $length < 0;

    my $end = $start->clone()->add( minutes => $length );

    # Sometimes the claimed length of the movie makes the movie end
    # a few minutes after the next movie is supposed to start.
    # Assume that next_start is correct.
    if( (defined $next_start ) and ($end > $next_start) )
    {
      $end = $next_start;
    }
    
    my $title = $sc->findvalue( './Program/@Title' );
    my $org_title = $sc->findvalue( './Program/@OriginalTitle' );
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
    
    # The director and actor info is in a somewhat strange format. 
    # Actor is a child of Director and the data seems to contain
    # all combinations of Actor and Director.

    my %directors;
    my @directors;
    my $ns2 = $sc->find( './/Director' );
  
    foreach my $dir ($ns2->get_nodelist)
    {
      my $name = norm( $dir->findvalue('./@Name') );
      if( not defined( $directors{ $name } ) )
      {
        $directors{$name} = 1;
        push @directors, $name;
      }
    }
    
    my %actors;
    my @actors;
    my $ns3 = $sc->find( './/Actor' );
  
    foreach my $act ($ns3->get_nodelist)
    {
      my $name = norm( $act->findvalue('./@Name') );
      if( not defined( $actors{ $name } ) )
      {
        $actors{$name} = 1;
        push @actors, $name;
      }
    }

    my $ce = {
      channel_id  => $chd->{id},
      title       => norm($title) || norm($org_title),
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

    if( scalar( @directors ) > 0 )
    {
      $ce->{directors} = join ", ", @directors;
    }

    if( scalar( @actors ) > 0 )
    {
      $ce->{actors} = join ", ", @actors;
    }

    $ds->AddProgramme( $ce );
  }
  
  # Success
  return 1;
}

sub create_dt
{
  my $self = shift;
  my( $str ) = @_;
  
  my( $date, $time ) = split( 'T', $str );

  if( not defined $time )
  {
    return undef;
  }
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

1;
