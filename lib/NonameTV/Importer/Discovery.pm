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

use NonameTV qw/MyGet Wordfile2Xml Htmlfile2Xml norm/;
use NonameTV::DataStore::Helper;
use NonameTV::DataStore::Updater;
use NonameTV::Log qw/info progress error logdie 
                     log_to_string log_to_string_result/;

use NonameTV::Importer;

use base 'NonameTV::Importer';

# The lowest log-level to store in the batch entry.
# DEBUG = 1
# INFO = 2
# PROGRESS = 3
# ERROR = 4
# FATAL = 5
my $BATCH_LOG_LEVEL = 4;

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

  my $sth = $self->{datastore}->Iterate( 'channels', 
                                         { grabber => 'discovery' },
                                         qw/xmltvid id grabber_info/ )
    or logdie "Failed to fetch grabber data";

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

  NonameTV::Log::verbose( $p->{verbose} );

  foreach my $file (@ARGV)
  {
    progress(  "Discovery: Processing $file" );
    $self->ImportFile( "", $file, $p );
  } 
}

sub ImportFile
{
  my $self = shift;
  my( $contentname, $file, $p ) = @_;

  my( $fnid, $fnlang, $fntype, $ext ) = 
    ( $file =~ /([A-Z]+[\. ]+[A-Z]+)[\. ]
               (\S+).*?
               (\S+\s*[0-9]*)\.
               ([^\.]+)$/x );

  if( not defined( $ext ) )
  {
    error( "Discovery: Unknown filename $file" );
    return;
  }

  $fnid =~ tr/ /./;

#  if( $fnlang ne "Swe" )
#  {
#    error( "Wrong language $fnlang" );
#    return;
#  }

  if( $fntype =~ /^high/i )
  {
    progress( "Discovery: Skipping highlights file $file" );
    return;
  }

  if( not exists( $self->{channel_data}->{$fnid} ) )
  {
    error( "Discovery: Unknown channel $fnid in $file" );
    return;
  }

  my $channel_id = $self->{channel_data}->{$fnid}->{id};
  my $channel_xmltvid = $self->{channel_data}->{$fnid}->{xmltvid};

  my $doc;
  if( $ext =~  /doc/i )
  {
    $doc = Wordfile2Xml( $file );
  }
  elsif( $ext eq 'html' )
  {
    $doc = Htmlfile2Xml( $file );
  }
  else
  {
    error( "Discovery: Unknown extension $ext in $file" );
    return;
  }

  if( not defined( $doc ) )
  {
    error( "Discovery: Failed to parse $file" );
    return;
  }

  if( $fntype =~ /^amend/i )
  {
    $self->ImportAmendments( $fnid, $file, $doc, 
                             $channel_xmltvid, $channel_id );
  }
  elsif( $fntype =~ /^final|rei/i )
  {
    $self->ImportData( $fnid, $file, $doc, 
                       $channel_xmltvid, $channel_id );
  }
  else
  {
    error( "Discovery: Unknown filetype $fntype for $file" );
    return;
  }
}

# Import files that contain full programming details,
# usually for an entire month.
# $doc is an XML::LibXML::Document object.
sub ImportData
{
  my $self = shift;
  my( $fnid, $filename, $doc, $channel_xmltvid, $channel_id ) = @_;
  
  my $dsh = $self->{datastorehelper};

  my $loghandle;

  # Find all div-entries.
  my $ns = $doc->find( "//div" );
  
  if( $ns->size() == 0 )
  {
    error( "Discovery: No programme entries found in $filename" );
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
        $loghandle = log_to_string( $BATCH_LOG_LEVEL ); 
        progress( "${channel_xmltvid}_$date: Processing $filename" );
	$dsh->StartBatch( "${channel_xmltvid}_$date", $channel_id );
	$dsh->StartDate( $date );
	$state = ST_FDATE;
	next;
      }
      else
      {
	error( "State ST_START, found: $text" );
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
	$dsh->EndBatch( 1, log_to_string_result( $loghandle ) );

        $loghandle = log_to_string( $BATCH_LOG_LEVEL ); 
        progress( "${channel_xmltvid}_$date: Processing $filename" );
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
	error( "Discovery: $filename State ST_FDATE, found: $text" );
      }
    }
    elsif( $state == ST_EPILOG )
    {
      if( ($type != T_TEXT) and ($type != T_DATE) )
      {
	error( "Discovery: $filename State ST_EPILOG, found: $text" );
      }
    }
  }
  $dsh->EndBatch( 1, log_to_string_result( $loghandle ) );
}

#
# Import data from a file that contains programme updates only.
# $doc is an XML::LibXML::Document object.
#
sub ImportAmendments
{
  my $self = shift;
  my( $fnid, $filename, $doc, $channel_xmltvid, $channel_id ) = @_;

  my $dsu = $self->{datastoreupdater};

  my $loghandle;

  # Find all div-entries.
  my $ns = $doc->find( "//div" );
  
  if( $ns->size() == 0 )
  {
    error( "Discovery: $filename: No programme entries found." );
    return;
  }

  use constant {
    ST_HEAD => 0,
    ST_FOUND_DATE => 1,
  };

  my $state=ST_HEAD;

  my( $date, $prevtime, $e );
  
  foreach my $div ($ns->get_nodelist)
  {
    my( $text ) = norm( $div->findvalue( './/text()' ) );
    next if $text eq "";

    my( $time, $command, $title );

    if( ($text =~ /^sida \d+ av \d+$/i) or
        ($text =~ /tablån fortsätter som tidigare/i) )
    {
      next;
    }
    elsif( $text =~ /^SLUT$/ )
    {
      last;
    }
    elsif( $text =~ /^(måndag|tisdag|onsdag|torsdag|fredag|lördag|söndag|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\s*\d+\s*\D+\s*\d+$/i  )
    {
      if( $state != ST_HEAD )
      {
        $self->process_command( $channel_id, $e )
          if( defined( $e ) );
        $e = undef;
        $dsu->EndBatchUpdate( 1, log_to_string_result( $loghandle ) )
          if( $self->{process_batch} ); 
      }

      $date = parse_date( $text );
      $state = ST_FOUND_DATE;

      $loghandle = log_to_string( $BATCH_LOG_LEVEL ); 
      progress( "${channel_xmltvid}_$date: Processing $filename" );

      $self->{process_batch} = 
        $dsu->StartBatchUpdate( "${channel_xmltvid}_$date", $channel_id ) ;

      $self->start_date( $date );
    }
    elsif( ($command, $title) = 
           ($text =~ /^([A-ZÅÄÖ][ A-ZÅÄÖ]+)\s
                       (.*?)\s*
                       ( \( [^)]* \) )*
                     $/x ) )
    {
      if( $state != ST_FOUND_DATE )
      {
        logdie( "Discovery: $filename Wrong state for $text" );
      }

      $self->process_command( $channel_id, $e )
        if defined $e;

      $e = $self->parse_command( $prevtime, $command, $title );
    }
    elsif( ($time, $command, $title) = 
           ($text =~ /^(\d\d[\.:]\d\d)\s
                       ([A-ZÅÄÖ][ A-ZÅÄÖ]+)\s+
                       ([A-ZÅÄÖ].*?)\s*
                       ( \( [^)]* \) )*
                     $/x ) )
    {
      if( $state != ST_FOUND_DATE )
      {
        logdie( "Discovery: $filename Wrong state for $text" );
      }

      $self->process_command( $channel_id, $e )
        if defined $e;

      $e = $self->parse_command( $time, $command, $title );

      $prevtime = $time;
    }
    elsif( $state == ST_FOUND_DATE )
    {
      # Plain text. This must be a description.
      if( defined( $e ) )
      {
        $e->{desc} .= $text;
        $self->process_command( $channel_id, $e );
        $e = undef;
      }
      else
      {
        error( "Discovery: $filename Ignored text: $text" );
      }
    }
    else
    {
      # Plain text in header. Ignore.
    }
  }
  $self->process_command( $channel_id, $e )
    if( defined( $e ) );

  $dsu->EndBatchUpdate( 1, log_to_string_result( $loghandle ) )
    if( $self->{process_batch} ); 
}

sub parse_command
{
  my $self = shift;
  my( $time, $command, $title ) = @_;

#  print "PC: $time - $command - $title\n";
  my $e;

  $e->{time} = $time;
  $e->{title} = $title;
  $e->{desc} = "";

  if( $command eq "ÄNDRA" or $command eq "RADERA")
  {
    $e->{command} = "DELETEBLIND";
  }
  elsif( $command eq "CHANGE" or $command eq "DELETE" )
  {
    # This is a document with changes in English.
    # The titles won't match.
    $e->{command} = "DELETEBLIND";
  }    
  elsif( $command eq "TILL" or $command eq "INFOGA" 
         or $command eq "TO" or $command eq "INSERT" )
  {
    $e->{command} = "INSERT";
  }
  elsif( $command eq "EJ ÄNDRAD" or $command eq "UNCHANGED")
  {
    $e->{command} = "IGNORE";
  }
  else
  {
    die "Unknown command $command with time $time";
  }

  return $e;
}

sub process_command
{
  my $self = shift;
  my( $channel_id, $e ) = @_;

#  print "DO: $e->{command} $e->{time} $e->{title}\n";

  return unless $self->{process_batch};

  my $dsu = $self->{datastoreupdater};

  my $dt = $self->create_dt( $e->{time} );

  return if $dt < DateTime->today;

  if( $e->{command} eq 'DELETEBLIND' )
  {
    my $ce = {
      channel_id => $channel_id,
      start_time => $dt->ymd('-') . " " . $dt->hms(':'),
    };      

    $self->{del_e} = $dsu->DeleteProgramme( $ce, 1 );
  }
  elsif( $e->{command} eq "INSERT" )
  {
    my $ce = {
      channel_id => $channel_id,
      start_time => $dt->ymd('-') . " " . $dt->hms(':'),
      title => $e->{title},
    };
    extract_extra_info( $ce );

    if( $e->{desc} =~ /Programförklaring ej ändrad/ )
    {
      # This is a program that has gotten a new title. It means
      # that it is a record CHANGE ... TO ... Thus, the description
      # is the same as the description from the record we just deleted.
      $ce->{description} = $self->{del_e}->{description};
    }
    else
    {
      $e->{description} = $e->{desc};
    }

    $dsu->AddProgramme( $ce );
  }    
  elsif( $e->{command} eq "IGNORE" )
  {}
  else
  {
    logdie( "Discovery: Unknown command $e->{command}" );
  }
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

  logdie( $self->{batch_id} . ": Unknown starttime $time" )
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
    print $self->{batch_id} . ": " . $dt->ymd('-') . " $hour:$minute: $@" ;
    $hour++;
    error( "Adjusting to $hour:$minute" );
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
