package NonameTV::Importer::Axess;

use strict;
use warnings;

=pod

Import data from Word-files delivered via e-mail. The parsing of the
data relies only on the text-content of the document, not on the
formatting.

Features:

=cut

use utf8;

use DateTime;
use XML::LibXML;

use NonameTV qw/MyGet File2Xml FindParagraphs norm/;
use NonameTV::DataStore::Helper;
use NonameTV::DataStore::Updater;
use NonameTV::Log qw/info progress error logdie/;

use NonameTV::Importer::BaseFile;
use base 'NonameTV::Importer::BaseFile';

sub new 
{
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);
  
  $self->{grabber_name} = "Axess";

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  my $dsu = NonameTV::DataStore::Updater->new( $self->{datastore} );
  $self->{datastoreupdater} = $dsu;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};

  my $doc = File2Xml( $file );

  if( not defined( $doc ) ) {
    error( "Axess: Failed to parse $file" );
    return;
  }

  $self->ImportData( $file, $doc, 
		     $channel_xmltvid, $channel_id );
}

# Import files that contain full programming details,
# usually for an entire week.
# $doc is an XML::LibXML::Document object.
sub ImportData {
  my $self = shift;
  my( $filename, $doc, $channel_xmltvid, $channel_id ) = @_;
  
  my $dsh = $self->{datastorehelper};

  my $paragraphs = FindParagraphs( $doc, '//.' );

  if( scalar( @{$paragraphs} ) == 0 ) {
    error( "Axess: No programme entries found in $filename" );
    return;
  }
  
  progress( "Axess: Processing $filename" );

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
  };
  
  my $state=ST_START;
  my $currdate;

  my $start;
  my $end;
  my $title;
  my $date;
  
  my $ce = {};
  
  foreach my $text (@{$paragraphs}) {
    my $type;
    
    if( $text =~ /^Kl\.\s
                  (mån|tis|ons|tors|fre|lör|sön)dagen\sden
                  \s*\d+\s*\D+$/ix ) {
      $date = parse_date( $text );
      if( not defined $date ) {
	error( "Axess: $filename Invalid date $text" );
	$type = T_TEXT;
      }
      else {
	$type = T_DATE;
      }
    }
    elsif( $text =~ /^\d\d\.\d\d\s*-\s*\d\d\.\d\d\s+\S+/ ) {
      $type = T_HEAD;
      $start=undef;
      $end=undef;
      $title=undef;

      ($start, $end, $title) = ($text =~ /^(\d+\.\d+)
				           \s*-\s*
                                           (\d+\.\d+)\s+
				           (.*)$/x );
      $start =~ tr/\./:/;
      $end =~ tr/\./\:/;
    }
    elsif( $text =~ /^\d\d\.\d\d\s+\S+/ ) {
      $type = T_HEAD;
      $start=undef;
      $end=undef;
      $title=undef;

      ($start, $title) = ($text =~ /^(\d+\.\d+)\s+
				     (.*)$/x );
      $start =~ tr/\./:/;
    }
    else {
      $type = T_TEXT;
    }
    
    if( $state == ST_START ) {
      if( $type == T_DATE ) {
	$dsh->StartBatch( "${channel_xmltvid}_$date", $channel_id );
	$dsh->StartDate( $date );
        $self->AddDate( $date );
	$state = ST_FDATE;
	next;
      }
      else {
#	error( "State ST_START, found: $text" );
      }
    }
    elsif( $state == ST_FHEAD ) {
      if( $type == T_TEXT ) {
	if( defined( $ce->{description} ) ) {
	  $ce->{description} .= " " . $text;
	}
	else {
	  $ce->{description} = $text;
	}
	next;
      }
      else {
	extract_extra_info( $ce );
	$dsh->AddProgramme( $ce );
	$ce = {};
	$state = ST_FDATE;
      }
    }
    
    if( $state == ST_FDATE ) {
      if( $type == T_HEAD ) {
	$ce->{start_time} = $start;
	$ce->{end_time} = $end if defined $end;
	$ce->{title} = $title;
	$state = ST_FHEAD;
      }
      elsif( $type == T_DATE ) {
	$dsh->EndBatch( 1 );

	$dsh->StartBatch( "${channel_xmltvid}_$date", $channel_id );
	$dsh->StartDate( $date );
        $self->AddDate( $date );
	$state = ST_FDATE;
      }
      elsif( $type == T_STOP ) {
	$state = ST_EPILOG;
      }
      else {
	error( "Axess: $filename State ST_FDATE, found: $text" );
      }
    }
    elsif( $state == ST_EPILOG ) {
      if( ($type != T_TEXT) and ($type != T_DATE) )
      {
	error( "Axess: $filename State ST_EPILOG, found: $text" );
      }
    }
  }
  $dsh->EndBatch( 1 );
}



sub extract_extra_info {
  my( $ce ) = shift;

  return;
}

my @months = qw/januari februari mars april maj juni juli augusti
    september oktober november december/;

my @shortmonths = qw/jan feb mar apr maj jun jul aug sept okt nov dec/;

my %monthnames = ();
for( my $i = 0; $i < scalar(@months); $i++ ) 
{ $monthnames{$months[$i]} = $i+1;}

for( my $i = 0; $i < scalar(@shortmonths); $i++ ) 
{ $monthnames{$shortmonths[$i]} = $i+1;}

sub parse_date {
  my( $text ) = @_;

  print "DateText: '$text'\n";

  my( $weekday, $day, $monthname ) = 
      ( $text =~ /^Kl. (\S+)\sden\s(\d+)\s*(\S+)$/ );
  print "Date: $monthname $day\n";
  my $month = $monthnames{lc $monthname};
  return undef unless defined( $month );

  my $year = (localtime(time))[5] + 1900;

  my $dt = DateTime->new( 
			  year   => $year,
			  month  => $month,
			  day    => $day,
			  hour   => 0,
			  minute => 0,
			  second => 0,
			  );

  if( $dt < DateTime->now->subtract( months => 3 ) ) {
    $dt = DateTime->new( 
			 year   => $year+1,
			 month  => $month,
			 day    => $day,
			 hour   => 0,
			 minute => 0,
			 second => 0,
			 );
  }

  return $dt->ymd('-');
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
