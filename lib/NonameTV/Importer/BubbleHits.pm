package NonameTV::Importer::BubbleHits;

use strict;
use warnings;

=pod

Import data from Excel files delivered via e-mail.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;
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

  $self->{grabber_name} = "BubbleHits";

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  # Only process .xls files.
  return if( $file !~ /\.xls$/i );
  progress( "BubbleHits: $xmltvid: Processing $file" );

  my %columns = ();
  my $date;
  my $currdate = "x";

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];

    if( $oWkS->{Name} !~ /Schedule/i ){
      progress( "BubbleHits: $chd->{xmltvid}: Skipping worksheet: $oWkS->{Name}" );
      next;
    }
    progress( "BubbleHits: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

    # the row with the column names is the 7th
    # get the names of the columns from the 1st row
    if( not %columns ){
      for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
        $columns{$oWkS->{Cells}[6][$iC]->Value} = $iC;
      }
#foreach my $cl (%columns) {
#print "$cl\n";
#}
    }


    # browse through rows
    # schedules are starting at row 8
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # date - column 0
      my $oWkC = $oWkS->{Cells}[$iR][0];
      next if( ! $oWkC );

      $date = ParseDate( $oWkC->Value );
      next if( ! $date );

      if( $date ne $currdate ){

        progress("BubbleHits: Date is $date");

        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

      # time - column 1
      $oWkC = $oWkS->{Cells}[$iR][1];
      next if( ! $oWkC );
      my $time = $oWkC->Value if( $oWkC->Value );

      # title - column 2
      $oWkC = $oWkS->{Cells}[$iR][2];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );

      # episode - column 3
      $oWkC = $oWkS->{Cells}[$iR][3];
      my $episode = $oWkC->Value if( $oWkC->Value );

      # synopsis - column 4
      $oWkC = $oWkS->{Cells}[$iR][4];
      my $synopsis = $oWkC->Value if( $oWkC->Value );

      # link - column 5
      $oWkC = $oWkS->{Cells}[$iR][5];
      my $link = $oWkC->Value if( $oWkC->Value );

      # genre - column 6
      $oWkC = $oWkS->{Cells}[$iR][6];
      my $genre = $oWkC->Value if( $oWkC->Value );

      # subgenre - column 7
      $oWkC = $oWkS->{Cells}[$iR][7];
      my $subgenre = $oWkC->Value if( $oWkC->Value );

      # rating - column 8
      $oWkC = $oWkS->{Cells}[$iR][8];
      my $rating = $oWkC->Value if( $oWkC->Value );

      # free to air or encrypted - column 9
      $oWkC = $oWkS->{Cells}[$iR][9];
      my $freeorenc = $oWkC->Value if( $oWkC->Value );

      progress("BubbleHits: $xmltvid: $time - $title");

      my $ce = {
        channel_id => $channel_id,
        start_time => $time,
        title => norm($title),
      };

      $ce->{description} = $synopsis if $synopsis;

      $dsh->AddProgramme( $ce );
    }

    %columns = ();

  }

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my ( $dinfo ) = @_;

  my( $day, $monthname, $year ) = ( $dinfo =~ /(\d+)\-(\S+)\-(\d+)/ );

  return undef if( ! $year );

  $year += 2000 if $year < 100;

  my $month;
  $month = 1 if( $monthname =~ /Jan/i );
  $month = 2 if( $monthname =~ /Feb/i );
  $month = 3 if( $monthname =~ /Mar/i );
  $month = 4 if( $monthname =~ /Apr/i );
  $month = 5 if( $monthname =~ /May/i );
  $month = 6 if( $monthname =~ /Jun/i );
  $month = 7 if( $monthname =~ /Jul/i );
  $month = 8 if( $monthname =~ /Aug/i );
  $month = 9 if( $monthname =~ /Sep/i );
  $month = 10 if( $monthname =~ /Oct/i );
  $month = 11 if( $monthname =~ /Nov/i );
  $month = 12 if( $monthname =~ /Dec/i );

  my $date = sprintf( "%04d-%02d-%02d", $year, $month, $day );
  return $date;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
