package NonameTV::Importer::Discovery;

use strict;
use warnings;

=pod

Import data from Word-files delivered via e-mail. The parsing of the
data relies only on the text-content of the document, not on the
formatting.

Features:

Episode numbers parsed from title.
Subtitles.

=cut

use utf8;

use DateTime;
use XML::LibXML;

use NonameTV qw/Content2Xml norm/;
use NonameTV::DataStore::Helper;
use NonameTV::DataStore::Updater;
use NonameTV::Log qw/w f/;

use NonameTV::Importer::BaseUnstructured;
use base 'NonameTV::Importer::BaseUnstructured';

my $command_re = "ÄNDRA|RADERA|TILL|INFOGA|EJ ÄNDRAD|" . 
    "CHANGE|DELETE|TO|INSERT|UNCHANGED";

my $time_re = '\d\d[\.:]\d\d';

sub new 
{
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);
  

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  my $dsu = NonameTV::DataStore::Updater->new( $self->{datastore} );
  $self->{datastoreupdater} = $dsu;

  return $self;
}

sub ImportContent {
  my $self = shift;
  my( $filename, $cref, $chd ) = @_;

  if( $filename =~ /\bhigh/i ) {
    f "Skipping highlights file";
    return 0;
  }

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};

  my $doc = Content2Xml( $cref );

  if( not defined( $doc ) ) {
    f "Failed to parse";
    return 0;
  }

  return $self->ImportDocument( $filename, $doc, 
			    $channel_xmltvid, $channel_id );
}

# Import files that contain full programming details,
# usually for an entire month.
# $doc is an XML::LibXML::Document object.
sub ImportDocument {
  my $self = shift;
  my( $filename, $doc, $channel_xmltvid, $channel_id ) = @_;
  
  my $dsh = $self->{datastorehelper};

  # Find all div-entries.
  my $ns = $doc->find( "//div" );
  
  if( $ns->size() == 0 ) {
    f "No programme entries found";
    return 0;
  }
  
  # States
  use constant {
    ST_START  => 0,
    ST_FDATE  => 1,   # Found date
    ST_FHEAD  => 2,   # Found head with starttime and title
    ST_FDESC  => 3,   # Found description
    ST_EPILOG => 4,   # After END-marker
  };
  
  use constant {
    T_HEAD => 10,
    T_DATE => 11,
    T_TEXT => 12,
    T_STOP => 13,
    T_HEAD_ENG => 14,
  };
  
  my $state=ST_START;
  my $currdate;

  my $start;
  my $title;
  my $date;
  
  my $ce = {};
  
  foreach my $div ($ns->get_nodelist) {
    # Ignore English titles in National Geographic.
    next if $div->findvalue( '@name' ) =~ /title in english/i;

    my( $text ) = norm( $div->findvalue( './/text()' ) );
    next if $text eq "";

 #   print "Text: $text\n";

    my $type;
    
    if( $text =~ /^(måndag|tisdag|onsdag|torsdag|fredag|lördag|söndag|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\s*\d+\s*\D+\s*\d+$/i )
    {
      $type = T_DATE;
      $date = parse_date( $text );
      if( not defined $date ) {
	w "Invalid date $text";
      }

    }
    elsif( $text =~ /^\d\d\.\d\d\s+\S+/ )
    {
      $type = T_HEAD;
      $start=undef;
      $title=undef;

      ($start, $title) = ($text =~ /^(\d+\.\d+)\s+(.*)\s*$/ );
      $start =~ tr/\./:/;
    }
    elsif( $text =~ /^\s*\(.*\)\s*$/ )
    {
      $type = T_HEAD_ENG;
    }
    elsif( $text =~ /^\s*END\s*$/ )
    {
      $type = T_STOP;
    }
    else
    {
      $type = T_TEXT;
    }
    
    if( $state == ST_START )
    {
      if( $type == T_TEXT )
      {
        if( $text =~ /M.nadskorrektur/ or 
	    $text =~ /Observera f.ljande .ndringar/ ) {
	    f "Ignoring amendments document.";
	    return 0;
	}
      }
      elsif( $type == T_DATE )
      {
	$dsh->StartBatch( "${channel_xmltvid}_$date", $channel_id );
	$dsh->StartDate( $date );
        $self->AddDate( $date );
	$state = ST_FDATE;
	next;
      }
      else
      {
        w "State ST_START, found: $text";
      }
    }
    elsif( $state == ST_FHEAD )
    {
      if( $type == T_TEXT )
      {
	if( defined( $ce->{description} ) )
	{
	  $ce->{description} .= " " . $text;
	}
	else
	{
	  $ce->{description} = $text;
	}
	next;
      }
      elsif( $type == T_HEAD_ENG )
      {}
      else
      {
	extract_extra_info( $ce );
	$dsh->AddProgramme( $ce );
	$ce = {};
	$state = ST_FDATE;
      }
    }
    
    if( $state == ST_FDATE )
    {
      if( $type == T_HEAD )
      {
	$ce->{start_time} = $start;
	$ce->{title} = $title;
	$state = ST_FHEAD;
      }
      elsif( $type == T_DATE )
      {
	$dsh->EndBatch( 1 );

	$dsh->StartBatch( "${channel_xmltvid}_$date", $channel_id );
	$dsh->StartDate( $date );
        $self->AddDate( $date );
	$state = ST_FDATE;
      }
      elsif( $type == T_STOP )
      {
	$state = ST_EPILOG;
      }
      else
      {
	w "State ST_FDATE, found: $text";
      }
    }
    elsif( $state == ST_EPILOG )
    {
      if( ($type != T_TEXT) and ($type != T_DATE) )
      {
	w "State ST_EPILOG, found: $text";
      }
    }
  }
  $dsh->EndBatch( 1 );

  return 1;
}

sub extract_extra_info
{
  my( $ce ) = shift;

  my( $episode ) = ($ce->{title} =~ /:\s*Avsnitt\s*(\d+)$/);
  $ce->{title} =~ s/:\s*Avsnitt\s*(\d+)$//; 
  $ce->{episode} = sprintf(" . %d . ", $episode-1)
    if defined( $episode );
  ( $ce->{subtitle} ) = ($ce->{title} =~ /:\s*(.+)$/);
  $ce->{title} =~ s/:\s*(.+)$//;

  $ce->{title} =~ s/^PREMI.R\s+//;

  if( $ce->{title} =~ /^\bs.ndningsslut\b$/i )
  {
    $ce->{title} = "end-of-transmission";
  }

  return;
}


sub parse_date
{
  my( $text ) = @_;

  my @months = qw/januari februari mars april maj juni juli augusti
      september oktober november december/;

  my @months_eng = qw/january february march april may june july
    august september october november december/;
  
  my %monthnames = ();
  for( my $i = 0; $i < scalar(@months); $i++ ) 
  { $monthnames{$months[$i]} = $i+1;}

  for( my $i = 0; $i < scalar(@months_eng); $i++ ) 
  { $monthnames{$months_eng[$i]} = $i+1;}
  
  my( $weekday, $day, $monthname, $year ) = 
      ( $text =~ /^(\S+?)\s*(\d+)\s*(\S+?)\s*(\d+)$/ );
  
  my $month = $monthnames{lc $monthname};
  return undef unless defined( $month );

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub start_date
{
  my $self = shift;
  my( $date ) = @_;

#  print "StartDate: $date\n";

  my( $year, $month, $day ) = split( '-', $date );
  $self->{curr_date} = DateTime->new( 
                                      year   => $year,
                                      month  => $month,
                                      day    => $day,
                                      hour   => 0,
                                      minute => 0,
                                      second => 0,
                                      time_zone => 'Europe/Stockholm' );
}


sub create_dt
{
  my $self = shift;
  my( $time ) = @_;

  my $dt = $self->{curr_date}->clone();
  
  my( $hour, $minute ) = split( /[:\.]/, $time );

  w "Unknown starttime $time"
    if( not defined( $minute ) );

  # The schedule date doesn't wrap at midnight. This is what
  # they seem to use.
  if( $hour < 9 )
  {
    $dt->add( days => 1 );
  }

  # Don't die for invalid times during shift to DST.
  my $res = eval {
    $dt->set( hour   => $hour,
              minute => $minute,
              );
  };

  if( not defined $res )
  {
    w $dt->ymd('-') . " $hour:$minute: $@" ;
    $hour++;
    w "Adjusting to $hour:$minute";
    $dt->set( hour   => $hour,
              minute => $minute,
              );
  }

  $dt->set_time_zone( "UTC" );

  return $dt;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
