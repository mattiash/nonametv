package NonameTV::Importer::Viasat;

use strict;
use warnings;

use DateTime;

use NonameTV::Importer;

use base 'NonameTV::Importer';

our $OptionSpec = [ qw/force-update/ ];
our %OptionDefaults = ( 
                        'force-update' => 0,
                        );

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
  my( $ds, $cache, $p ) = @_;
  
  my $sth = $ds->Iterate( 'channels', { grabber => 'viasat' },
                          qw/id grabber_info/ )
    or die "Failed to fetch grabber data";

  while( my $data = $sth->fetchrow_hashref )
  {
    my $dt = DateTime->today->set_time_zone( 'Europe/Stockholm' );

    my( $content, $error );

    do
    {
      my $batch_id = $data->{'grabber_info'} . $dt->week_year . '-' . 
        $dt->week_number;

      my $url = $self->{UrlRoot} . $batch_id . '_tab.txt';

      print "Fetching listings for $batch_id\n";

      ( $content, $error ) = $cache->get( $url );

      if ( defined( $content ) and
           ($p->{'force-update'} or ($error==2) ) )
      {
        my @rows = split("\n", $content);
        my $columns = [ split( "\t", $rows[0] ) ];

        $ds->StartBatch( $batch_id );

        my $previous_start = undef;
        my $prev_entry = undef;

        for ( my $i = 1; $i < scalar @rows; $i++ )
        {
          my $inrow = row_to_hash($rows[$i], $columns );
                    
          #print "Title: " . $inrow->{'name'} . "\n";
          #-----------------CALCULATE START TIME -------------------
          my $start_time;
          
          if ( exists($inrow->{'Date'}) )
          {
            $start_time = DateTime->new( 
                  year   => substr($inrow->{'Date'},0,4),
                  month  => substr($inrow->{'Date'},5,2),
                  day    => substr($inrow->{'Date'},8,2),
                  time_zone => 'Europe/Stockholm',
                                         );
          }
          elsif (defined($previous_start))
          {
            $start_time = $previous_start->clone;
          }
          else
          {
            die "No time in this or previous";
          }
          
          $start_time->set (	hour => substr($inrow->{'Start time'}, 0, 2),
                                minute => substr($inrow->{'Start time'}, 3, 2),
                                second => 0,
                                );

          if (defined($previous_start))
          {
            if (DateTime->compare( $start_time, $previous_start) == -1)
            {
              $start_time = $start_time->add( days => 1 );
            }
          }

          my $st = $start_time->clone();
          $st->set_time_zone( 'UTC' );
          my $start_time_str = $st->ymd('-') . " " . $st->hms(':');

          #print "Start time done: " . $start_time->strftime('%F %T') . "\n";

          # The starttime of this show is the endtime of the previous show,
          # so now we can add the previous show
          if( defined $prev_entry )
          {
            $prev_entry->{end_time} = $start_time_str;
            $ds->AddProgramme( $prev_entry );
            $prev_entry = undef;
          }

          if ($inrow->{'name'} eq "SLUT")
          {
            next;
          }

          #---------------FIX DESCRIPTION-----------------------
          my $description = $inrow->{Logline}; 

          if (exists( $inrow->{'Synopsis this episode'} ) )
          {
            $description .=  " " . $inrow->{'Synopsis this episode'};
          }

          $description = norm( $description );

          #-----------------WRAP IT UP ---------------------------
          $prev_entry = {
            channel_id => $data->{id},
            title => $inrow->{'name'},
            description => $description,
            start_time => $start_time_str,
            episode_nr => $inrow->{'episode nr'},
            season_nr => $inrow->{'Season number'},
            Bline => $inrow->{'B-line'},
            Category => $inrow->{'Category'},
            Genre => $inrow->{'Genre'},
            };

          $previous_start = $start_time;
        }

        $ds->EndBatch( 1 );
      }
      elsif( not defined( $error ) )
      {
        print "No changes.\n";
      }

      $dt = $dt->add( days => 7 );
    } while( defined( $content ) );
  }
}

sub row_to_hash
{
  my( $row, $columns ) = @_;

  my @coldata = split( "\t", $row );
  my %res;
  
  for( my $i=0; $i<scalar(@coldata); $i++ )
  {
    $res{$columns->[$i]} = norm($coldata[$i])
      if $coldata[$i] =~ /\S/; 
  }

  return \%res;
}

# Delete leading and trailing space from a string.
# Convert all whitespace to spaces. Convert multiple
# spaces to a single space.
sub norm
{
    my( $str ) = @_;

    return "" if not defined( $str );

    $str =~ s/^\s+//;
    $str =~ s/\s+$//;

    $str =~ tr/\n\r\t /    /s;

    # Strange quote-sign.
    $str =~ tr/\x93\x94\x96/""-/;

    return $str;
}

1;
