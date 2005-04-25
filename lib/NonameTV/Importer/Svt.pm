package NonameTV::Importer::Svt;

=pod

Old importer for xml-files delivered via mail from Svt. Requires
the xml-files to be split into one file per day and channel and
put on a website before they can be imported.

This importer has been obsoleted by Svt_xml and Svt_web.

=cut

use strict;
use warnings;

use DateTime;
use XML::LibXML;
use IO::Wrap;

use NonameTV::Importer;
use NonameTV qw/MyGet Utf8Conv/;

use base 'NonameTV::Importer';

our $OptionSpec = [ qw/force-update verbose/ ];
our %OptionDefaults = ( 
                        'force-update' => 0,
                        verbose        => 0,
                        );

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";
    $self->{MaxDays} = 32 unless defined $self->{MaxDays};
    return $self;
}

sub Import
{
  my $self = shift;
  my( $p ) = @_;
  
  my $ds = $self->{datastore};

  my $sth = $ds->Iterate( 'channels', { grabber => 'svt' },
                          qw/id grabber_info xmltvid/ )
    or die "Failed to fetch grabber data";

  while( my $data = $sth->fetchrow_hashref )
  {
    my $dt = DateTime->today->set_time_zone( 'Europe/Stockholm' );

    my( $content, $code );
    my $days = 0;

    for( my $days=0; $days < $self->{MaxDays}; $days++ )
    {
      my $batch_id = $data->{xmltvid} . "_" . $dt->ymd("-");

      print "Fetching listings for $batch_id\n"
        if( $p->{verbose} );

      ( $content, $code ) = $self->FetchData( $batch_id, $data );
            
      if( not defined( $content ) )
      {
        print "No data for for $batch_id\n"
          if $p->{verbose};
      }
      elsif ( ($p->{'force-update'} or ($code) ) )
      {
        print "Processing listings for $batch_id\n"
          if $p->{verbose};

        my $xml = XML::LibXML->new;
        my $doc;
        eval { $doc = $xml->parse_string($content); };
        if( $@ ne "" )
        {
          print STDERR "$batch_id Failed to parse\n";
          goto nextDay;
        }

        $ds->StartBatch( $batch_id );

        my $ns = $doc->find( "//program" );

        foreach my $p ($ns->get_nodelist)
        {
          my $title = $p->findvalue('title/text()');
          my $start_date = $p->findvalue( 'date_utc/text()' );
          my $start_time = $p->findvalue( 'start_time_utc/text()' );
          my $length_min = $p->findvalue( 'length_minutes/text()' );

          my $description = $p->findvalue( 'long_description_complete/text()' );

          my $start = create_dt( $start_date, $start_time );
          my $end = $start->clone()->add( minutes => $length_min );

          $ds->AddProgramme( {
            channel_id  => $data->{id},
            title       => norm($title),
            description => norm($description),
            start_time  => $start->ymd("-") . " " . $start->hms(":"),
            end_time    => $end->ymd("-") . " " . $end->hms(":"),
          } );            
        }
        
        $ds->EndBatch(1);
      }
      $dt = $dt->add( days => 1 );
    }
  }
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
