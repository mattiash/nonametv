package NonameTV::Importer::TV4;

#
# This importer imports data from TV4's press service. 
#
# Note that the importer always skips the last programme in the
# dataset, since programmes have no stop-time. This is usually four weeks
# from now. 
# 
# Furthermore, the last programme for each days schedule (as grouped by TV4) 
# gets a batch-id belonging to the next day, since that is where the stop-time 
# can be found.
#
# The assumption that a program stops when the next program starts is
# sometimes wrong, but there is no better data available.
#

# BUG!! If TV4 simply adds more data, we will always miss the last show
# of each day, since the last show for the last day is not stored the first 
# time it is seen (unknown stoptime) and when the schedule for another day 
# is released, we don't re-process the schedule for the old last day since it
# hasn't changed.
#

use strict;
use warnings;

use DateTime;
use XML::LibXML;
use Text::Iconv;

use NonameTV qw/MyGet/;

use NonameTV::Importer;

use base 'NonameTV::Importer';

our $OptionSpec = [ qw/force-update verbose/ ];
our %OptionDefaults = ( 
                        'force-update' => 0,
                        'verbose'      => 0,
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
  
  my $sth = $ds->Iterate( 'channels', { grabber => 'tv4' },
                          qw/xmltvid id grabber_info/ )
    or die "Failed to fetch grabber data";

  while( my $data = $sth->fetchrow_hashref )
  {
    
    # Start with yesterdays schedule, since it contains data
    # for today as well.

    my $dt = DateTime->today->set_time_zone( 'Europe/Stockholm' );
    $dt = $dt->subtract( days => 1 );

    my $done = 0;

    # Keep track if anything has changed for this channel.
    # If we detect changes for one day, we must keep on updating
    # all the following days, since the changes spill over due
    # to the stop time of the last show being on the schedule for
    # tomorrow.
    # 
    # This algorithm could be improved a lot, but is it worth it?
    #
    my $process = 0;

    my $curr_entry = undef;

    do
    {
      my $batch_id = $data->{xmltvid} . "_" . $dt->ymd();

      print "Fetching listings for $batch_id\n"
        if( $p->{verbose} );

      my( $content, $code ) = $self->FetchData( $batch_id, $data );

      # Should we process entries for this batch or can we skip them?
      $process = ($process or $p->{'force-update'} or ($code) );
      
      if (defined( $content ) ) 
      {        
        my $xml = XML::LibXML->new;
        my $doc;
        eval { $doc = $xml->parse_string($content); };
        if( $@ ne "" )
        {
          print STDERR "$batch_id Failed to parse\n";
          $done = 1;
          goto nextDay;
        }

        $ds->StartBatch( $batch_id ) 
          if $process;

        print "Processing listings for $batch_id\n"
          if( $process and $p->{verbose} );
        
        # Find all "program"-entries.
        my $ns = $doc->find( "//program" );
        if( $ns->size() == 0 )
        {
          # This means that there is no data for this day or any 
          # of the following days. Exit.
          $done = 1;
          $ds->EndBatch(0)
            if $process;
          next;
        }

        my $curr_date = $dt->clone();
        my $last_start_dt = $curr_date;

        foreach my $pgm ($ns->get_nodelist)
        {
          my $starttime = $pgm->findvalue( 'transmissiontime' );
          
          my $start_dt = create_dt( $curr_date, $starttime );

          if( $start_dt < $last_start_dt )
          {
            $curr_date = $curr_date->add(days => 1);
            $start_dt = $start_dt->add(days => 1);
          }
          
          $last_start_dt = $start_dt;

          if( defined $curr_entry )
          {
            $curr_entry->{end_time} = $start_dt->ymd("-") . " " . 
                                        $start_dt->hms(":");

            $ds->AddProgramme( $curr_entry )
              if $process;
          }

          my $title =$pgm->findvalue( 'title' );
          my $description = $pgm->findvalue( 'description' );

          $curr_entry = 
            {
              channel_id  => $data->{id},
              title       => norm($title),
              description => norm($description),
              start_time  => $start_dt->ymd("-") . " " . 
                               $start_dt->hms(":"),
            };
        }
        
        $ds->EndBatch( 1 )
          if $process;
      }
      else
      {
        print STDERR "Failed to fetch data for $batch_id\n";
        $done = 1;
      }
       
      $dt = $dt->add( days => 1 );

    nextDay:

    } while( not $done );
  }

  $sth->finish();
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my( $date ) = ($batch_id =~ /_(.*)/);

  my $url = $self->{UrlRoot} . '?todo=search&r1=XML'
    . '&firstdate=' . $date
    . '&lastdate=' . $date 
    . '&channel=' . $data->{grabber_info};
    
  my( $content, $code ) = MyGet( $url );
  return( $content, $code );
}

sub create_dt
{
  my( $date, $time ) = @_;
  
  my( $hour, $minute ) = split( ":", $time );
  
  my $dt = $date->clone();
  
  $dt->set( hour => $hour, minute => $minute );
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
