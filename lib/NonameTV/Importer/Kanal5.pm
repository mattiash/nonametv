package NonameTV::Importer::Kanal5;

use strict;
use warnings;

use DateTime;
use XML::LibXML;
use Text::Iconv;

use NonameTV qw/MyGet/;

use NonameTV::Importer;

use base 'NonameTV::Importer';

our $OptionSpec = [ qw/force-update/ ];
our %OptionDefaults = ( 
                        'force-update' => 0,
                        );

my $conv = Text::Iconv->new("UTF-8", "ISO-8859-1" );

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    return $self;
}

sub Import
{
  my $self = shift;
  my( $ds, $p ) = @_;
  
  my $sth = $ds->Iterate( 'channels', { grabber => 'kanal5' },
                          qw/id grabber_info/ )
    or die "Failed to fetch grabber data";

  while( my $data = $sth->fetchrow_hashref )
  {
    my $dt = DateTime->today->set_time_zone( 'Europe/Stockholm' );

    my( $content, $code );

    do
    {
      my $batch_id = "kanal5_" . $dt->week_year . '-' . 
        $dt->week_number;

      my $url = $self->{UrlRoot} . "tab" . $dt->strftime("%W%y") . ".xml";

      print "Fetching listings for $batch_id\n";

      ( $content, $code ) = MyGet( $url );
            
      if ( defined( $content ) and
           ($p->{'force-update'} or ($code) ) )
      {
        $ds->StartBatch( $batch_id );
        
        my $xml = XML::LibXML->new;
        my $doc = $xml->parse_string($content);
        # Find all "TRANSMISSION"-entries.
        my $ns = $doc->find( "//TRANSMISSION" );
        
        foreach my $tm ($ns->get_nodelist)
        {
          # Sanity check. 
          # What does it mean if there are several transmissionparts?
          die "Wrong number of transmissionparts for transmission " .
            $tm->findvalue( '@oid' )
            if( $tm->findvalue( 'count(.//TRANSMISSIONPART)' ) ) != 1;
          
          my $tm_p = 
            ($tm->find( '(.//TRANSMISSIONPART)[1]' )->get_nodelist)[0];
          
          my $title =$tm->findvalue(
            './/PRODUCTTITLE[.//PSIPRODUCTTITLETYPE/@oid="131708570"]/@title');
          
          if( $title =~ /^\s*$/ )
          {
            # Some entries lack a title. 
            # Fallback to the title in the TRANSMISSION-tag.
            $title = $tm->findvalue( '@title' );
          }
          
          my $startdate = $tm_p->findvalue( './/start[1]/TIMEINSTANT[1]/@date'
                                            );
          my $starttime = $tm_p->findvalue( './/start[1]/TIMEINSTANT[1]/@time'
                                            );
          my $start = create_dt( $startdate, $starttime );
          
          my $enddate = $tm_p->findvalue( './/end[1]/TIMEINSTANT[1]/@date' );
          my $endtime = $tm_p->findvalue( './/end[1]/TIMEINSTANT[1]/@time' );
          my $end = create_dt( $enddate, $endtime );
          
          my $description = $tm->findvalue( './/shortdescription[1]' );
          
          $ds->AddProgramme( {
            channel_id  => $data->{id},
            title       => norm($title),
            description => norm($description),
            start_time  => $start->ymd("-") . " " . $start->hms(":"),
            end_time    => $end->ymd("-") . " " . $end->hms(":"),
#            episode_nr => $inrow->{'episode nr'},
#            season_nr => $inrow->{'Season number'},
#            Bline => $inrow->{'B-line'},
#            Category => $inrow->{'Category'},
#            Genre => $inrow->{'Genre'},
          } );            
        }
        
        $ds->EndBatch( 1 );
      }  
       
      $dt = $dt->add( days => 7 );

    } while( defined( $content ) );
  }
}

sub create_dt
{
  my( $date, $time ) = @_;
  
  my( $year, $month, $day ) = split( '-', $date );
  
  # Remove the dot and everything after it.
  $time =~ s/\..*$//;
  
  my( $hour, $minute, $second ) = split( ":", $time );
  
  my $dayadd = 0;
  
  if( $hour > 23 )
  {
    $hour -= 24;
    $dayadd = 1;
  }
  
  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          second => $second,
                          time_zone => 'Europe/Stockholm',
                          );
  
  $dt->add( days => $dayadd ) if $dayadd;
  $dt->set_time_zone( "UTC" );
  
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
