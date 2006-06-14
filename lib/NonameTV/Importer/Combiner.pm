package NonameTV::Importer::Combiner;

=pod

Combine several channels into one. Read data from xmltv-files downloaded
via http.

Replace Span-modules with custom routines. Treat times as strings.
Remove Day-handling, I can always add it back in if any channel
requires it.

=cut 

use strict;
use warnings;


my %channel_data;

=pod 
_Bakgrund:_Discovery Mix är en s k promotion-kanal för Discoverys 5 tv-kanaler: Discovery, Animal Planet, Discovery Civilization, Discovery Sci-Trek och Discovery Travel & Adventure.

Discovery Mix sänder från de olika Discoverykanalernas dagliga program. Discovery Mix plockar det program som visas på respektive kanal vid en fastställd tidpunkt. Det är en 5 minuters paus mellan varje kanalbyte och i två fall pauser på 25 minuter.

Kanalen sänds bara hos Com Hem, som sköter bytet mellan inslagen från de olika kanalerna enligt den tidtabell som Discovery lagt upp.

_Här är tablån för Discovery Mix: _

07.00-09.00 Animal Planet

09.00-09.50 Discovery Travel & Adventure

09.55-10.45 Discovery Sci-Trek

10.50-11.40 Discovery Civilization

11.45-12.35 Discovery Travel & Adventure

PAUS

13.00-15.00 Animal Planet

15.00-15.50 Discovery Travel & Adventure

15.55-16.45 Discovery Sci-Trek

16.50-17.40 Discovery Civilization

17.45-18.35 Discovery Travel & Adventure

PAUS

19.00-21.00 Animal Planet

21.00-01.00 Discovery Channel

=cut

$channel_data{ "nordic.mix.discovery.com" } =
  { 
    "nordic.discovery.com" => 
      [ 
        {
          day => 'all',
          time => "2100-0100",
        },
      ],
    "nordic.animalplanet.discovery.com" =>
      [
        {
          day => 'all',
          time => "0700-0900"
        },
        {
          day => 'all',
          time => "1300-1500"
        },
        {
          day => 'all',
          time => "1900-2100"
        },
      ],
    "nordic.travel.discovery.com" =>
      [
        {
          day => 'all',
          time => "0900-0950",
        },
        {
          day => 'all',
          time => "1145-1235",
        },
        {
          day => 'all',
          time => "1500-1550"
        },
        {
          day => 'all',
          time => "1745-1835",
        },

      ],
    "nordic.science.discovery.com" =>
      [
        {
          day => 'all',
          time => "0955-1045",
        },
        {
          day => 'all',
          time => "1555-1645"
        },
      ],
    "nordic.civilisation.discovery.com" =>
      [
        {
          day => 'all',
          time => "1050-1140",
        },
        {
          day => 'all',
          time => "1650-1740"
        },
      ],
  };

=pod

Barnkanalen och Kunskapskanalen samsänder via DVB-T.
Vad jag vet är det aldrig några överlapp, så jag
inkluderar alla program på båda kanalerna.

=cut

$channel_data{ "kunskapbarn.svt.se" } =
  { 
    "barnkanalen.svt.se" => 
      [ 
        {
          day => 'all',
        },
      ],
    "kunskapskanalen.svt.se" =>
      [
        {
          day => 'all',
        },
      ],
  };

=pod

Viasat Nature/Crime och Nickelodeon samsänder hos SPA.
Vad jag vet är det aldrig några överlapp, så jag
inkluderar alla program på båda kanalerna.

=cut

$channel_data{ "viasat-nature-nick.spa.se" } =
  { 
    "nature.viasat.se" => 
      [ 
        {
          day => 'all',
        },
      ],
    "nickelodeon.se" =>
      [
        {
          day => 'all',
        },
      ],
  };

use DateTime;
use XML::LibXML;
use Compress::Zlib;
use DateTime::Event::Recurrence;

use NonameTV qw/MyGet/;

use NonameTV::Importer::BaseDaily;

use NonameTV::Log qw/info progress error logdie/;

use NonameTV::Importer;

use base 'NonameTV::Importer';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{MaxDays} = 32 unless defined $self->{MaxDays};
    $self->{MaxDaysShort} = 2 unless defined $self->{MaxDaysShort};

    $self->{OptionSpec} = [ qw/force-update verbose short-grab/ ];
    $self->{OptionDefaults} = { 
      'force-update' => 0,
      'verbose'      => 0,
      'short-grab'   => 0,
    };

    $self->{grabber_name} = "Combiner";

    $self->ProcessSchedules();
    return $self;
}

sub Import
{
  my $self = shift;
  my( $p ) = @_;
  
  NonameTV::Log::verbose( $p->{verbose} );

  my $maxdays = $p->{'short-grab'} ? $self->{MaxDaysShort} : $self->{MaxDays};

  my $ds = $self->{datastore};

  my $sth = $ds->Iterate( 'channels', { grabber => $self->{grabber_name} } )
      or logdie( "$self->{grabber_name}: Failed to fetch grabber data" );

  while( my $data = $sth->fetchrow_hashref )
  {
    if( not exists( $channel_data{$data->{xmltvid} } ) )
    {
      logdie( "Unknown channel '$data->{xmltvid}'" );
    }

    if( $p->{'force-update'} and not $p->{'short-grab'} )
    {
      # Delete all data for this channel.
      my $deleted = $ds->Delete( 'programs', { channel_id => $data->{id} } );
      progress( "Deleted $deleted records for $data->{xmltvid}" );
    }

    my $start_dt = DateTime->today->subtract( days => 1 );

    for( my $days = 0; $days <= $maxdays; $days++ )
    {
      my $dt = $start_dt->clone;
      $dt=$dt->add( days => $days );

      my $batch_id = $data->{xmltvid} . "_" . $dt->ymd('-');

      info( "$batch_id: Fetching data" );

      my %ch_content;
      my $changed = 0;
      my $error = 0;

      foreach my $chan (keys %{$channel_data{$data->{xmltvid}}})
      {
        my $curr_batch = $data->{xmltvid}. "_" . $chan . "_" . $dt->ymd('-');
        my( $content, $code ) = $self->FetchData( $curr_batch, $data );

        $ch_content{$chan} = $content;
        $changed = 1 if $code;
        $error = 1 if not defined( $content );
      }

      if( ($error==0) and ($p->{'force-update'} or $changed)  )
      {
        progress( "$batch_id: Processing data" );

        # Process the gzipped xml-files into an array of program-
        # entries.
        my %prog;
        foreach my $ch (keys %ch_content)
        {
          my $xmldata = Compress::Zlib::memGunzip( \($ch_content{$ch}) );
          $prog{$ch} = $self->ParseXmltv( \$xmldata );
        }

        my $progs = $self->BuildDay( $batch_id, \%prog, 
                                     $channel_data{$data->{xmltvid}}, $data );
      }
      elsif( $error )
      {
        error( "$batch_id: Failed to fetch data" );
      }
    }
  }

  $sth->finish();
}

sub BuildDay
{
  my $self = shift;
  my( $batch_id, $prog, $sched, $chd ) = @_;

  my $ds =$self->{datastore};

  my @progs;

  my( $channel, $date ) = split( /_/, $batch_id );

  $ds->StartBatch( $batch_id );

  foreach my $subch (keys %{$sched})
  {
    my $ss = $self->{spanset}->{$channel}->{$subch};

    foreach my $e (@{$prog->{$subch}})
    {
      my $span = DateTime::Span->from_datetimes( 
        after => $e->{start_dt}, before => $e->{stop_dt} );

      if( $ss->contains( $span ) )
      {
        # Include this program
#        print "Full: $e->{title}\n";
      }
      elsif( $ss->intersects( $span ) )
      {
        # Include the part of this program that 
        # is sent.
#        print "Part: $e->{title}\n";
        my $isect = $ss->intersection( $span );
        my @spans = $isect->as_list();
        if( scalar(@spans) != 1 )
        {
          error( "$batch_id: Multiple spans" );
        }
        $e->{start_dt} = $spans[0]->start;
        $e->{stop_dt} = $spans[0]->end;
        $e->{title} = "(P) " . $e->{title};
      }
      else
      {
#        print "Skip: $e->{title}\n";
        next;
      }

      $e->{start_dt}->set_time_zone( "UTC" );
      $e->{stop_dt}->set_time_zone( "UTC" );
  
      $e->{start_time} = $e->{start_dt}->ymd('-') . " " . 
        $e->{start_dt}->hms(':');
      delete $e->{start_dt};
      $e->{end_time} = $e->{stop_dt}->ymd('-') . " " . 
        $e->{stop_dt}->hms(':');
      delete $e->{stop_dt};
      $e->{channel_id} = $chd->{id};
      
      $ds->AddProgrammeRaw( $e );
    }
  }
  $ds->EndBatch( 1 );
}

sub ParseXmltv
{
  my $self = shift;
  my( $cref ) = @_;

  if( not defined $self->{xml} )
  {
    $self->{xml} = XML::LibXML->new;
  }
  
  my $doc;
  eval { 
    $doc = $self->{xml}->parse_string($$cref); 
  };
  if( $@ ne "" )
  {
    error( "???: Failed to parse: $@" );
    return;
  }

  my @d;

  # Find all "programme"-entries.
  my $ns = $doc->find( "//programme" );
  if( $ns->size() == 0 )
  {
#    error( "???: No data found" );
    return;
  }
  
  foreach my $pgm ($ns->get_nodelist)
  {
    my $start = $pgm->findvalue( '@start' );
    my $start_dt = create_dt( $start );

    my $stop = $pgm->findvalue( '@stop' );
    my $stop_dt = create_dt( $stop );

    my $title = $pgm->findvalue( 'title' );
    my $subtitle = $pgm->findvalue( 'sub-title' );
    
    my $desc = $pgm->findvalue( 'desc' );
    my $cat1 = $pgm->findvalue( 'category[1]' );
    my $cat2 = $pgm->findvalue( 'category[2]' );
    my $episode = $pgm->findvalue( 'episode-num[@system="xmltv_ns"]' );
    my $production_date = $pgm->findvalue( 'date' );

    my $aspect = $pgm->findvalue( 'video/aspect' );

    my %e = (
      start_dt => $start_dt,
      stop_dt => $stop_dt,
      title => $title,
      description => $desc,
    );

    if( $subtitle =~ /\S/ )
    {
      $e{subtitle} = $subtitle;
    }

    if( $episode =~ /\S/ )
    {
      $e{episode} = $episode;
    }

    if( $cat1 =~ /^[a-z]/ )
    {
      $e{program_type} = $cat1;
    }
    elsif( $cat1 =~ /^[A-Z]/ )
    {
      $e{category} = $cat1;
    }

    if( $cat2 =~ /^[a-z]/ )
    {
      $e{program_type} = $cat2;
    }
    elsif( $cat2 =~ /^[A-Z]/ )
    {
      $e{category} = $cat2;
    }

    if( $production_date =~ /\S/ )
    {
      $e{production_date} = $production_date;
    }

    if( $aspect =~ /\S/ )
    {
      $e{aspect} = $aspect;
    }
    
    push @d, \%e;
  }

  return \@d;
}

sub ProcessSchedules
{
  my $self = shift;

  foreach my $channel (keys %channel_data)
  {
    foreach my $subch (keys %{$channel_data{$channel}})
    {
      $self->{spanset}->{$channel}->{$subch} 
        = DateTime::SpanSet->empty_set();

      foreach my $e (@{$channel_data{$channel}->{$subch}})
      {
        my $spanset;

        if( $e->{day} eq "all" )
        {
          if( defined( $e->{time} ) )
          {
            my($fromhour, $frommin, $tohour, $tomin) =
              ($e->{time} =~ /^(\d\d)(\d\d)-(\d\d)(\d\d)$/ );
            
            my $start = DateTime::Event::Recurrence->daily
              ( hours => [$fromhour], minutes => [$frommin] );
            
            my $end   = DateTime::Event::Recurrence->daily
              ( hours => [$tohour], minutes => [$tomin] );
            
            # Build a spanset from the set of starting points and ending points
            $spanset = DateTime::SpanSet->from_sets
              ( start_set => $start,
                end_set   => $end );
          }
          else
          {
            $spanset = DateTime::Span->from_datetime_and_duration( 
                start => DateTime->today->subtract( days => 10 ), 
                duration => DateTime::Duration->new( months => 4 ) );
          }
        }
        else
        {
          die "Unknown day $e->{day}";
        }

        $self->{spanset}->{$channel}->{$subch} = 
          $self->{spanset}->{$channel}->{$subch}->union( $spanset );
      } 
    }
  }
}

sub create_dt
{
  my( $datetime ) = @_;

  my( $year, $month, $day, $hour, $minute, $second, $tz ) = 
    ($datetime =~ /(\d{4})(\d{2})(\d{2})
                   (\d{2})(\d{2})(\d{2})\s+
                   (\S+)$/x);
  
  my $dt = DateTime->new( 
                          year => $year,
                          month => $month, 
                          day => $day,
                          hour => $hour,
                          minute => $minute,
                          second => $second,
                          time_zone => $tz 
                          );
  
  return $dt;
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my( $id ) = ($batch_id =~ /_(.*)/);

  my $url = $self->{UrlRoot} . $id . '.xml.gz';

  my( $content, $code ) = MyGet( $url );

  if( not defined( $content ) )
  {
    print "$url failed.\n";
  }
  return( $content, $code );
}
    
1;
