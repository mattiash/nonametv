package NonameTV::Importer::Sailing;

use strict;
use warnings;

=pod

channel: Sailing

Import data from Excel-files delivered via e-mail.
Each file contains one sheet, one sheet per month.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;

use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error 
                     log_to_string log_to_string_result/;
use NonameTV qw/AddCategory norm/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  $self->{grabber_name} = "Sailing";

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

  my( $dateinfo );
  my( $when, $starttime );
  my( $title );
  my( $oBook, $oWkS, $oWkC );

  # Only process .xls files.
  return if $file !~  /\.xls$/i;
  progress( "Sailing: $xmltvid: Processing $file" );
  
  my $currdate = "x";

  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];

    progress( "Sailing: $xmltvid: Processing worksheet: $oWkS->{Name}" );

    # check if there is data in the sheet
    # sometimes there are some hidden empty sheets
    next if( ! $oWkS->{MaxRow} );
    next if( ! $oWkS->{MaxCol} );

    # data layout in the sheet:
    # - all data for one month are in one sheet
    # - every day takes 2 columns - odd column = time, even column = title
    # - 5th row contains day names and dates (in even columns)
    # - schedules start from 6th row

    for(my $iC = 0; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC+=2) {

      # dateinfo (dayname and date) is in the 5th row
      $oWkC = $oWkS->{Cells}[4][$iC];
      if( $oWkC ){
        $dateinfo = $oWkC->Value;
      }
      next if ( ! $dateinfo );

      my $date = ParseDate( $dateinfo );
      next if ( ! $date );

      if( $date ne $currdate ){

        progress("Sailing: $xmltvid: Date is: $date");

        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

      # programmes start from row 6
      for(my $iR = 5 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

        # Time Slot
        $oWkC = $oWkS->{Cells}[$iR][$iC];
        if( $oWkC ){
          $when = $oWkC->Value;
        }
        # next if when is empty
        next if ( ! $when );
        next if( $when !~ /^\d+:\d+$/ );

        # Title
        $oWkC = $oWkS->{Cells}[$iR][$iC+1];
        if( $oWkC ){
          $title = $oWkC->Value;
        }
        # next if title is empty as it spreads across more cells
        next if ( ! $title );
        next if( $title !~ /\S+/ );

        # create the time
        $starttime = create_dt( $date , $when );

        progress("Sailing: $xmltvid: $starttime - $title");

        my $ce = {
          channel_id   => $channel_id,
          start_time   => $starttime->hms(":"),
          title        => $title,
        };

        $dsh->AddProgramme( $ce );

      } # next row (next show)

      $dateinfo = undef;
      $when = undef;
      $title = undef;
    } # next column (next day)

  } # next worksheet

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my ( $dinfo ) = @_;

  return undef if( $dinfo !~ /^\S+,\s+\d+\s+\S+\s+\d+$/ );

  my( $dn, $d, $mn, $y ) = ( $dinfo =~ /(\S+),\s+(\d+)\s+(\S+)\s+(\d+)/ );

  my $month;
  $month = 1 if( $mn =~ /January/i );
  $month = 2 if( $mn =~ /February/i );
  $month = 3 if( $mn =~ /March/i );
  $month = 4 if( $mn =~ /April/i );
  $month = 5 if( $mn =~ /May/i );
  $month = 6 if( $mn =~ /June/i );
  $month = 7 if( $mn =~ /July/i );
  $month = 8 if( $mn =~ /August/i );
  $month = 9 if( $mn =~ /September/i );
  $month = 10 if( $mn =~ /October/i );
  $month = 11 if( $mn =~ /November/i );
  $month = 12 if( $mn =~ /December/i );

  return sprintf( "%4d-%02d-%02d", $y, $month, $d );
}
  
sub create_dt
{
  my ( $dinfo , $tinfo ) = @_;

  my( $year, $month, $day ) = ( $dinfo =~ /(\d+)-(\d+)-(\d+)/ );
  my( $hour, $min ) = ( $tinfo =~ /(\d+):(\d+)/ );

  my $dt = DateTime->new( year   => $year,
                           month  => $month,
                           day    => $day,
                           hour   => $hour,
                           minute => $min,
                           second => 0,
                           time_zone => 'Europe/Zagreb',
                           );

  # times are in CET timezone in original XLS file
  #$dt->set_time_zone( "UTC" );

  return( $dt );
}
  
1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
