package NonameTV::Importer::VH1_xls;

use strict;
use warnings;

=pod

channel: VH1 Europe, VH1 Classic Europe

Import data from Excel-files delivered via e-mail.
Each file contains more sheets, one sheet per week.

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

  $self->{grabber_name} = "VH1_xls";

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

  my( $dayname , $dateinfo );
  my( $when, $newtime );
  my( $title );
  my( $day, $month , $year );
  my( $oBook, $oWkS, $oWkC );

  # Only process .xls files.
  return if $file !~  /\.xls$/i;
  progress( "VH1_xls: $xmltvid: Processing $file" );
  
  my $currdate = "x";

  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];

    progress( "VH1_xls: $xmltvid: Processing worksheet: $oWkS->{Name}" );

    # check if there is data in the sheet
    # sometimes there are some hidden empty sheets
    next if( ! $oWkS->{MaxRow} );
    next if( ! $oWkS->{MaxCol} );

    # Each column contains data for one day
    # starting with column 1 for monday to column 7 for sunday
    for(my $iC = 1; $iC <= 7 ; $iC++) {

      # DAYNAME is in the 4th row
      $oWkC = $oWkS->{Cells}[3][$iC];
      if( $oWkC ){
        $dayname = $oWkC->Value;
      }
      next if ( ! $dayname );

      # DATE is in the 5th row
      $oWkC = $oWkS->{Cells}[4][$iC];
      if( $oWkC ){
        $dateinfo = $oWkC->Value;
      }
      next if ( ! $dateinfo );
      next if( $dateinfo !~ /^\d+-\d+-\d+$/ );

      ( $day , $month , $year ) = ParseDate( $dateinfo );
      my $date = sprintf( "%04d-%02d-%02d" , $year, $month, $day );

      progress("VH1_xls: $xmltvid: Date is: $date");

      if( $date ne $currdate ){

        progress("Bnet: Date is $date");

        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "05:00" );
        $currdate = $date;
      }

      # programmes start from row 6
      for(my $iR = 5 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

        # Time Slot
        $oWkC = $oWkS->{Cells}[$iR][0];
        if( $oWkC ){
          $when = $oWkC->Value;
        }
        # next if when is empty
        next if ( ! $when );
        next if( $when !~ /\d\d\d\d/ );

        # Title
        $oWkC = $oWkS->{Cells}[$iR][$iC];
        if( $oWkC ){
          $title = $oWkC->Value;
        }
        # next if title is empty as it spreads across more cells
        next if ( ! $title );
        next if( $title !~ /\S+/ );

        # from a valid cell with the 'title'
        # the following cells up to the next row that has valid 'when'
        # the cells might contain subtitle
        my $subtitle = undef;
        for( my $r = $iR + 1 ; defined $oWkS->{MaxRow} && $r <= $oWkS->{MaxRow} ; $r++ ){

          next if( ! $oWkS->{Cells}[$r][0] );
          next if( ! $oWkS->{Cells}[$r][$iC] );

          last if( $oWkS->{Cells}[$r][0]->Value );

          if( ! $oWkS->{Cells}[$r][0]->Value and $oWkS->{Cells}[$r][$iC]->Value ){
            $subtitle .= $oWkS->{Cells}[$r][$iC]->Value;
          }
        }

        # create the time
        $newtime = create_dt( $day , $month , $year , $when );

        progress("VH1_xls: $xmltvid: $newtime - $title");

        my $ce = {
          channel_id   => $channel_id,
          start_time   => $newtime->hms(":"),
          title        => $title,
        };

        if( defined $subtitle ){
          $ce->{subtitle} = $subtitle;
        }

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

  my( $m, $d, $y ) = ( $dinfo =~ /(\d+)-(\d+)-(\d+)/ );

  $y += 2000 if $y < 2000;

  return( $d , $m , $y );
}
  
sub create_dt
{
  my ( $d , $m , $y , $tinfo ) = @_;

  my( $hr, $mn ) = ( $tinfo =~ /(\d{2})(\d{2})/ );

  my $dt = DateTime->new( year   => $y,
                           month  => $m,
                           day    => $d,
                           hour   => $hr,
                           minute => $mn,
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
