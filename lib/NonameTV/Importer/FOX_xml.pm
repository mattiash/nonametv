package NonameTV::Importer::FOX_xml;

use strict;
use warnings;

=pod

Import data from Xml-files delivered via e-mail.  Each
day is handled as a separate batch.

Features:

=cut

use utf8;

use DateTime;
use XML::LibXML;
use Archive::Zip;
use Data::Dumper;
use File::Temp qw/tempfile/;

use NonameTV qw/norm AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/info progress error logdie 
                     log_to_string log_to_string_result/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  $self->{grabber_name} = "FOX_xml";

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  # there is no date information in the document
  # the first and last dates are known from the file name
  # which is in format 'FOX Crime schedule 28 Apr - 04 May CRO.xml'
  # as each day is in one worksheet, other days are
  # calculated as the offset from the first one
  my $dayoff = 0;
  my $year = DateTime->today->year();

  return if( $file !~ /\.xml$/i );
  progress( "FOX_xml: $xmltvid: Processing $file" );
  
  my( $month, $firstday ) = ExtractDate( $file );
  if( not defined $firstday ) {
    error( "FOX_xml $file: Unable to extract date from file name" );
    next;
  }

  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_file($file); };

  if( not defined( $doc ) ) {
    error( "FOX_xml $file: Failed to parse xml" );
    return;
  }
  my $wksheets = $doc->findnodes( "//ss:Worksheet" );
  
  if( $wksheets->size() == 0 ) {
    error( "FOX_xml $file: No Worksheets found" ) ;
    return;
  }

  my $batch_id;

  my $currdate = "x";
  my $column;

  # find the rows in the worksheet
  foreach my $wks ($wksheets->get_nodelist) {

    # the name of the worksheet
    my $dayname = $wks->getAttribute('ss:Name');
    progress("FOX_xml: $xmltvid: found worksheet named '$dayname'");

    # the path should point exactly to one worksheet
    my $rows = $wks->findnodes( ".//ss:Row" );
  
    if( $rows->size() == 0 ) {
      error( "FOX_xml $xmltvid: No Rows found in Worksheet '$dayname'" ) ;
      return;
    }

    foreach my $row ($rows->get_nodelist) {

      # the column names are stored in the first row
      # so read them and store their column positions
      # for further findvalue() calls
      if( not defined( $column ) ) {
        my $cells = $row->findnodes( ".//ss:Cell" );
        my $i = 1;
        $column = {};
        foreach my $cell ($cells->get_nodelist) {
	  my $v = $cell->findvalue( "." );
	  $column->{$v} = "ss:Cell[$i]";
	  $i++;
        }

        # Check that we found the necessary columns.

        next;
      }

      my $timeslot = norm( $row->findvalue( $column->{'Time Slot'} ) );
      my $title = norm( $row->findvalue( $column->{'EN Title'} ) );
      my $crotitle = norm( $row->findvalue( $column->{'Croatian Title'} ) );
      my $genre = norm( $row->findvalue( $column->{'Genre'} ) );

      if( ! $timeslot ){
        next;
      }

      my $starttime = create_dt( $year , $month , $firstday , $dayoff , $timeslot );

      my $date = $starttime->ymd('-');

      if( $date ne $currdate ) {
        if( $currdate ne "x" ) {
	  $dsh->EndBatch( 1 );
        }

        my $batch_id = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;
      }

      if( not defined( $starttime ) ) {
        error( "Invalid start-time '$date' '$starttime'. Skipping." );
        next;
      }

      progress( "FOX_xml: $xmltvid: $starttime - $title" );

      my $ce = {
        channel_id => $channel_id,
        title => $crotitle,
        subtitle => $title,
        start_time => $starttime->hms(':'),
      };

      if( $genre ){
        my($program_type, $category ) = $ds->LookupCat( 'FOX', $genre );
        AddCategory( $ce, $program_type, $category );
      }
    
      $dsh->AddProgramme( $ce );

    } # next row

    $column = undef;
    $dayoff++;

  } # next worksheet

  $dsh->EndBatch( 1 );

  return;
}

sub ExtractDate {
  my( $fn ) = @_;
  my $month;

  # format of the file name could be
  # 'FOX Crime schedule 28 Apr - 04 May CRO.xml'
  # or
  # 'Life Programa 05 - 11 May 08 CRO.xml'

  # try the first format
  my( $day , $monname ) = ($fn =~ m/\s(\d\d)\s(\S+)\s/ );
  
  # try the second if the first failed
  if( not defined( $monname ) or ( $monname eq '-' ) ) {
    ( $day , $monname ) = ($fn =~ m/\s(\d\d)\s\-\s\d\d\s(\S+)\s/ );
  }

  if( not defined( $day ) ) {
    return undef;
  }

  $month = 1 if( $monname eq 'Jan' );
  $month = 2 if( $monname eq 'Feb' );
  $month = 3 if( $monname eq 'Mar' );
  $month = 4 if( $monname eq 'Apr' );
  $month = 5 if( $monname eq 'May' );
  $month = 6 if( $monname eq 'Jun' );
  $month = 7 if( $monname eq 'Jul' );
  $month = 8 if( $monname eq 'Aug' );
  $month = 9 if( $monname eq 'Sep' );
  $month = 10 if( $monname eq 'Oct' );
  $month = 11 if( $monname eq 'Nov' );
  $month = 12 if( $monname eq 'Dec' );

  return ($month,$day);
}

sub create_dt {
  my ( $yr , $mn , $fd , $doff , $timeslot ) = @_;

  my ( $hour, $minute ) = ( $timeslot =~ /^\d{4}-\d{2}-\d{2}T(\d\d):(\d\d):/ );

  my $dt = DateTime->new( year   => $yr,
                          month  => $mn,
                          day    => $fd,
                          hour   => $hour,
                          minute => $minute,
                          second => 0,
                          nanosecond => 0,
                          time_zone => 'Europe/Zagreb',
  );

  # add dayoffset number of days
  $dt->add( days => $doff );

  #$dt->set_time_zone( "UTC" );

  return $dt;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
