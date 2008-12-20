package NonameTV::Importer::NGCHD;

#use strict;
#use warnings;

=pod

Import data from Xls files delivered via e-mail.  Each
day is handled as a separate batch.

Features:

=cut

use utf8;

use DateTime;
use Encode;
use Encode::Guess;
use Spreadsheet::ParseExcel;
use Data::Dumper;
use File::Temp qw/tempfile/;

use NonameTV qw/norm AddCategory MonthNumber/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);


  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  if( $file =~ /\.xls$/i ){
    $self->ImportXLS( $file, $channel_id, $channel_xmltvid );
  }

  return;
}

sub ImportXLS
{
  my $self = shift;
  my( $file, $channel_id, $channel_xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my %columns = ();
  my $date;
  my $currdate = "x";

  progress( "NGCHD: $channel_xmltvid: Processing $file" );

  my( $oBook, $oWkS, $oWkC );
  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  if( not defined( $oBook ) ) {
    error( "NGCHD: $file: Failed to parse xls" );
    return;
  }

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];
    progress("NGCHD: $channel_xmltvid: processing worksheet named '$oWkS->{Name}'");

    # read the rows with data
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      if( not %columns ){

        # the column names are stored in the row
        # where columns contain: CET-1, CET, CET+1, PROGRAM/ Emisió

        my $found = 0;

        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          if( $oWkS->{Cells}[$iR][$iC] ){
            $columns{$oWkS->{Cells}[$iR][$iC]->Value} = $iC;

            if( $oWkS->{Cells}[$iR][$iC]->Value =~ /CET-1/ ){
              $columns{DATE} = $iC;
            }

            if( $oWkS->{Cells}[$iR][$iC]->Value =~ /PROGRAM\/\s+Emis/ ){
              $columns{PROGRAM} = $iC;
              $found = 1;
            }

          }
        }

        %columns = () if not $found;
        next;
      }
#foreach my $cl (%columns) {
#print "$cl\n";
#}

      # Date (it is stored in the column 'CET-1'
      $oWkC = $oWkS->{Cells}[$iR][$columns{'CET-1'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      if( isDate( $oWkC->Value ) ){

        $date = ParseDate( $oWkC->Value );

        if( $date ne $currdate ) {
          if( $currdate ne "x" ) {
	    $dsh->EndBatch( 1 );
          }

          my $batch_id = $channel_xmltvid . "_" . $date;
          $dsh->StartBatch( $batch_id , $channel_id );
          $dsh->StartDate( $date , "08:00" );
          $currdate = $date;

          progress("NGCHD: $channel_xmltvid: Date is: $date");
        }

        next;
      }

      # Time Slot
      $oWkC = $oWkS->{Cells}[$iR][$columns{'CET'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $starttime = $oWkC->Value;

      if( not defined( $starttime ) ) {
        error( "Invalid start-time '$date' '$starttime'. Skipping." );
        next;
      }

      # Title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'PROGRAM'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $program = $oWkC->Value;

      my( $title, $episode ) = ParseShow( $program );

      progress( "NGCHD: $channel_xmltvid: $starttime - $title" );

      my $ce = {
        channel_id => $channel_id,
        title => $title,
        start_time => $starttime,
      };

      if( $episode ){
        $ce->{episode} = sprintf( ". %d .", $episode-1 );
      }

      $dsh->AddProgramme( $ce );

    } # next row

    %columns = ();

  } # next worksheet

  $dsh->EndBatch( 1 );

  return;
}

sub isDate
{
  my ( $text ) = @_;

  # the format is '01-10-08'
  if( $text =~ /^\d{2}-\d{2}-\d{2}$/ ){
    return 1;
  }

  return 0;
}

sub ParseDate
{
  my ( $dinfo ) = @_;

  # the format is '01-10-08'
  my( $day, $month, $year ) = ( $dinfo =~ /^(\d+)-(\d+)-(\d+)$/ );

  return undef if( ! $year );

  $year += 2000 if $year < 100;

  return sprintf( "%04d-%02d-%02d", $year, $month, $day );
}

sub ParseShow
{
  my ( $text ) = @_;

  my( $title, $episode );

  if( $text =~ /^.*:\s+Episode\s+\d+/ ){
    ( $title, $episode ) = ( $text =~ /(.*):\s+Episode\s+(\d+)/ );
  } else {
    $title = $text;
  }

  return( $title, $episode );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
