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

use DateTime;
use XML::LibXML;

use NonameTV qw/MyGet Wordfile2Xml Htmlfile2Xml Utf8Conv/;
use NonameTV::DataStore::Helper;

use NonameTV::Importer;

use base 'NonameTV::Importer';

sub new 
{
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);
  
  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  my $sth = $self->{datastore}->Iterate( 'channels', 
                                         { grabber => 'discovery' },
                                         qw/xmltvid id grabber_info/ )
    or die "Failed to fetch grabber data";

  while( my $data = $sth->fetchrow_hashref )
  {
    $self->{channel_data}->{$data->{grabber_info}} = 
                            { id => $data->{id},
                              xmltvid => $data->{xmltvid} 
                            };
  }

  $sth->finish;

    $self->{OptionSpec} = [ qw/force-update verbose/ ];
    $self->{OptionDefaults} = { 
      'force-update' => 0,
      'verbose'      => 0,
    };

  return $self;
}

sub Import
{
  my $self = shift;
  my( $p ) = @_;

  foreach my $file (@ARGV)
  {
    print  "Discovery: Processing $file\n";
    $self->ImportFile( "", $file, $p );
  } 
}

sub ImportFile
{
  my $self = shift;
  my( $contentname, $file, $p ) = @_;

  print "Processing $file.\n"
    if( $p->{verbose} );
  
  my( $fnid, $fnmon, $ext ) = 
    ( $file =~ /([A-Z\.]+)
               \.Swe\s+(.*)\.
               ([^\.]+)$/x );

  if( not defined( $fnmon ) )
  {
    print "Unknown filename $file\n";
    return;
  }

  if( $fnmon eq "High" )
  {
    print "Skipping highlights file.\n"
      if( $p->{verbose} );
    return;
  }

  if( not exists( $self->{channel_data}->{$fnid} ) )
  {
    print "Discovery: Unknown channel $fnid in $file\n";
    return;
  }

  my $channel_id = $self->{channel_data}->{$fnid}->{id};
  my $channel_xmltvid = $self->{channel_data}->{$fnid}->{xmltvid};

  my $dsh = $self->{datastorehelper};

  my $doc;
  if( $ext eq 'doc' )
  {
    $doc = Wordfile2Xml( $file );
  }
  elsif( $ext eq 'html' )
  {
    $doc = Htmlfile2Xml( $file );
  }
  else
  {
    print "Discovery: Unknown extension $ext\n";
  }

  if( not defined( $doc ) )
  {
    print STDERR "$file failed to parse\n";
    return;
  }

  # Find all div-entries.
  my $ns = $doc->find( "//div" );
  
  if( $ns->size() == 0 )
  {
    print STDERR "$file: No programme entries found.\n";
    return;
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
  
  foreach my $div ($ns->get_nodelist)
  {
    my( $text ) = norm( $div->findvalue( './/text()' ) );
    my( $divname ) = norm( $div->findvalue( '@name' ) );
    next if $text eq "";

 #   print "Text: $text\n";

    my $type;
    
    if( $text =~ /^\D+\s*\d+\s*\D+\s*\d+$/  )
    {
      $type = T_DATE;
      $date = parse_date( $text );
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
        # Ignore
      }
      elsif( $type == T_DATE )
      {
	$dsh->StartBatch( "${channel_xmltvid}_$date", $channel_id );
	$dsh->StartDate( $date );
	$state = ST_FDATE;
	next;
      }
      else
      {
	warn "State ST_START, found: $text\n";
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
	$state = ST_FDATE;
      }
      elsif( $type == T_STOP )
      {
	$state = ST_EPILOG;
      }
      else
      {
	warn "State ST_FDATE, found: $text\n";
      }
    }
    elsif( $state == ST_EPILOG )
    {
      if( ($type != T_TEXT) and ($type != T_DATE) )
      {
	warn "State ST_EPILOG, found: $text\n";
      }
    }
  }
  $dsh->EndBatch( 1 );

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
  
  my %monthnames = ();
  for( my $i = 0; $i < scalar(@months); $i++ ) 
  { $monthnames{$months[$i]} = $i+1;}
  
  my( $weekday, $day, $monthname, $year ) = 
      ( $text =~ /^(\S+?)\s*(\d+)\s*(\S+?)\s*(\d+)$/ );
  
  my $month = $monthnames{$monthname};
  return undef unless defined( $month );

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

# Delete leading and trailing space from a string.
# Convert all whitespace to spaces. Convert multiple
# spaces to a single space.
sub norm
{
    my( $instr ) = @_;

    return "" if not defined( $instr );

    my $str = Utf8Conv( $instr );

    $str =~ s/^\s+//;
    $str =~ s/\s+$//;

    $str =~ tr/\n\r\t /    /s;

    return $str;
}

1;
