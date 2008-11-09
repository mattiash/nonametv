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
use NonameTV::Log qw/progress error/;
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
      next if( ! $oWkC );
      my $dayname = $oWkC->Value;
      next if ( ! $dayname );

      # DATE is in the 5th row
      $oWkC = $oWkS->{Cells}[4][$iC];
      next if( ! $oWkC );
      my $dateinfo = $oWkC->Value;
      next if ( ! $dateinfo );
      next if( $dateinfo !~ /^\d+-\d+-\d+$/ and $dateinfo !~ /^\d+\/\d+\/\d+$/ );

      my $date = ParseDate( $dateinfo );

      progress("VH1_xls: $xmltvid: Date is: $date");

      if( $date ne $currdate ){

        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;
      }

      # programmes start from row 6
      for(my $iR = 5 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

        # Time Slot
        $oWkC = $oWkS->{Cells}[$iR][0];
        next if( ! $oWkC );
        my $timeinfo = $oWkC->Value;
        next if ( ! $timeinfo );
        next if( $timeinfo !~ /\d\d\d\d/ );
        my $time = ParseTime( $timeinfo );

        # Title
        $oWkC = $oWkS->{Cells}[$iR][$iC];
        next if( ! $oWkC );
        my $title = $oWkC->Value;
        next if ( ! $title );
        next if( $title !~ /\S+/ );

        # from a valid cell with the 'title'
        # the following cells up to the next row that has valid 'time'
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

        progress("VH1_xls: $xmltvid: $time - $title");

        my $ce = {
          channel_id   => $channel_id,
          start_time   => $time,
          title        => $title,
        };

        $ce->{subtitle} = $subtitle if $subtitle;

        $dsh->AddProgramme( $ce );

      } # next row (next show)

    } # next column (next day)

  } # next worksheet

  $dsh->EndBatch( 1 );

  return;
}

sub ParseTime
{
  my ( $tinfo ) = @_;

  my( $h, $m ) = ( $tinfo =~ /^(\d{2})(\d{2})$/ );

  return sprintf( "%02d:%02d", $h, $m );
}

sub ParseDate
{
  my ( $dinfo ) = @_;

  my( $m, $d, $y );

  if( $dinfo =~ /^\d+-\d+-\d+$/ ){
    ( $m, $d, $y ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $dinfo =~ /^\d+\/\d+\/\d+$/ ){
    ( $d, $m, $y ) = ( $dinfo =~ /^(\d+)\/(\d+)\/(\d+)$/ );
  } else {
    return undef;
  }

  $y += 2000 if $y < 100;

  return sprintf( "%04d-%02d-%02d" , $y, $m, $d );
}
  
1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
