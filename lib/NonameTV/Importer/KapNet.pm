package NonameTV::Importer::KapNet;

use strict;
use warnings;

=pod

Import data from Excel-files delivered via e-mail.
Each file is for one week.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;

use NonameTV::DataStore::Helper;
use NonameTV::Log qw/info progress error logdie 
                     log_to_string log_to_string_result/;
use NonameTV qw/AddCategory norm/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  $self->{grabber_name} = "KapNet";

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;
  my( $dateinfo );
  my( $kada, $newtime, $lasttime );
  my( $title, $newtitle , $lasttitle , $newdescription , $lastdescription );
  my( $day, $month , $year , $hour , $min );
  my( $oBook, $oWkS, $oWkC );

  # Only process .xls files.
  return if $file !~  /\.xls$/i;

  progress( "KapNet: Processing $file" );
  
  $self->{fileerror} = 0;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;

  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];

    # process only the sheet with the name PPxle
    #next if ( $oWkS->{Name} !~ /PPxle/ );

    progress( "KapNet: Processing worksheet: $oWkS->{Name}" );

    my $batch_id = $xmltvid . "_" . $file;
    $ds->StartBatch( $batch_id , $channel_id );

    # Date & Day info is in the first row
    $oWkC = $oWkS->{Cells}[0][1];
    if( $oWkC ){
      $dateinfo = $oWkC->Value;
    }
    next if ( ! $dateinfo );
    next if( $dateinfo !~ /\S.*\S/ );

    ( $day , $month , $year ) = ParseDate( $dateinfo );

    progress("KapNet: Processing day: $day / $month / $year ($dateinfo)");

    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # Time Slot
      $oWkC = $oWkS->{Cells}[$iR][0];
      if( $oWkC ){
        $kada = $oWkC->Value;
      }

      # next if kada is empty
      next if ( ! $kada );
      next if( $kada !~ /\S.*\S/ );

      # Title
      $oWkC = $oWkS->{Cells}[$iR][1];
      if( $oWkC ){
        $title = $oWkC->Value;
      }

      # next if title is empty as it spreads across more cells
      next if ( ! $title );
      next if( $title !~ /\S.*\S/ );

      # create the time
      $newtime = create_dt( $day , $month , $year , $kada );

      # all data is in one string which has to be split
      # to title and description
      if( $title =~ /: / ){
        ( $newtitle , $newdescription ) = split( ':', $title );
      } else {
        $newtitle = $title;
        $newdescription = '';
      }

      if( defined( $lasttitle ) and defined( $newtitle ) ){

        if( $newtime < $lasttime ){
          $newtime->add( days => 1 );
        }

        progress("KapNet: $lasttime - $newtime : $lasttitle");

        my $ce = {
          channel_id   => $channel_id,
          start_time   => $lasttime->ymd("-") . " " . $lasttime->hms(":"),
          end_time     => $newtime->ymd("-") . " " . $newtime->hms(":"),
          title        => $lasttitle,
          description  => $lastdescription,
        };

        $ds->AddProgramme( $ce );
      }

      if( defined( $newtime ) ){
        $lasttime = $newtime;
        $lasttitle = $newtitle;
        $lastdescription = $newdescription;
      }

    } # next row (next show)

    $ds->EndBatch( 1 );

  } # next worksheet

  return;
}

sub ParseDate
{
  my ( $dinfo ) = @_;

  my( $d, $m ) = ( $dinfo =~ /(\d+)\.(\d+)/ );

  my $y = DateTime->today()->year;

  return( $d , $m , $y );
}
  
sub create_dt
{
  my ( $d , $m , $y , $tinfo ) = @_;

  my( $hr, $mn ) = ( $tinfo =~ /(\d+)\:(\d+)/ );

  my $dt = DateTime->new( year   => $y,
                           month  => $m,
                           day    => $d,
                           hour   => $hr,
                           minute => $mn,
                           second => 0,
                           time_zone => 'Europe/Zagreb',
                           );

  # times are in CET timezone in original XLS file
  $dt->set_time_zone( "UTC" );

  return( $dt );
}
  
1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
