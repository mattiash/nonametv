package NonameTV::Importer::HRT;

use strict;
use warnings;

=pod

Importer for data from HRT. 
One file per channel and 4-day period downloaded from their site.
The downloaded file is in xml-format.

Features:

=cut

use DateTime;
use XML::LibXML;

use NonameTV qw/MyGet norm AddCategory/;
use NonameTV::Log qw/info progress error logdie/;

use NonameTV::Importer::BaseOne;

use base 'NonameTV::Importer::BaseOne';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{grabber_name} = "HRT";

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
  
  # Find all "programme"-entries.
  my $ns = $doc->find( "//programme" );
  
  foreach my $sc ($ns->get_nodelist)
  {
    
    #
    # start time
    #
    my $start = $self->create_dt( $sc->findvalue( './@start' ) );
    if( not defined $start )
    {
      error( "$batch_id: Invalid starttime '" . $sc->findvalue( './@start' ) . "'. Skipping." );
      next;
    }

    #
    # end time
    #
    my $end = $self->create_dt( $sc->findvalue( './@stop' ) );
    if( not defined $end )
    {
      error( "$batch_id: Invalid endtime '" . $sc->findvalue( './@stop' ) . "'. Skipping." );
      next;
    }
    
    #
    # title, subtitle
    #
    my $title = $sc->getElementsByTagName('title');
    my $org_title = $sc->getElementsByTagName('sub-title');
    
    #
    # description
    #
    my $desc  = $sc->getElementsByTagName('desc');
    
    #
    # genre
    #
    my $genre = norm($sc->getElementsByTagName( 'genre' ));

    #
    # production year
    #
    my $production_year = $sc->getElementsByTagName( 'date' );

    #
    # episode number
    #
    my $episode = $sc->getElementsByTagName( 'episode-num' );

    # The director and actor info is in a somewhat strange format. 
    # Actor is a child of Director and the data seems to contain
    # all combinations of Actor and Director.

#    my %directors;
#    my @directors;
#    my $ns2 = $sc->find( './/director' );

#    foreach my $dir ($ns2->get_nodelist)
#    {
#      my $name = norm( $dir->findvalue('./@Name') );
#      if( not defined( $directors{ $name } ) )
#      {
#        $directors{$name} = 1;
#        push @directors, $name;
#      }
#    }
    
#    my %actors;
#    my @actors;
#    my $ns3 = $sc->find( './/actor' );
  
#    foreach my $act ($ns3->get_nodelist)
#    {
#      my $name = norm( $act->findvalue('./@Name') );
#      if( not defined( $actors{ $name } ) )
#      {
#        $actors{$name} = 1;
#        push @actors, $name;
#      }
#    }

    my $ce = {
      channel_id  => $chd->{id},
      title       => norm($title) || norm($org_title),
      description => norm($desc),
      start_time  => $start->ymd("-") . " " . $start->hms(":"),
      end_time    => $end->ymd("-") . " " . $end->hms(":"),
#      aspect      => $sixteen_nine ? "16:9" : "4:3", 
    };

    if( defined( $episode ) )
    {
      #$ce->{episode} = $episode;
      #$ce->{program_type} = 'series';
    }

    my($program_type, $category ) = $ds->LookupCat( "HRT", $genre );

    AddCategory( $ce, $program_type, $category );

    if( defined( $production_year ) and ($production_year =~ /(\d\d\d\d)/) )
    {
      $ce->{production_date} = "$1-01-01";
    }

#    if( scalar( @directors ) > 0 )
#    {
#      $ce->{directors} = join ", ", @directors;
#    }

#    if( scalar( @actors ) > 0 )
#    {
#      $ce->{actors} = join ", ", @actors;
#    }

    $ds->AddProgramme( $ce );
  }
  
  # Success
  return 1;
}

sub create_dt
{
  my $self = shift;
  my( $str ) = @_;
  
  my $year = substr( $str , 0 , 4 );
  my $month = substr( $str , 4 , 2 );
  my $day = substr( $str , 6 , 2 );
  my $hour = substr( $str , 8 , 2 );
  my $minute = substr( $str , 10 , 2 );
  my $second = substr( $str , 12 , 2 );
  my $offset = substr( $str , 15 , 5 );

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
                          time_zone => 'Europe/Zagreb',
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
  #my $dt = DateTime->new( year=>$year, day => 4 );
  #$dt->add( days => $week * 7 - $dt->day_of_week - 6 );

  my $url = $self->{UrlRoot} . "\?$data->{grabber_info}";

  my( $content, $code ) = MyGet( $url );
  return( $content, $code );
}

1;
