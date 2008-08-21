package NonameTV::Importer::CNBCEuro;

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

use NonameTV qw/norm AddCategory MonthNumber/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error 
                     log_to_string log_to_string_result/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  $self->{grabber_name} = "CNBCEuro";

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
  progress( "CNBCEuro: $xmltvid: Processing $file" );

  my %columns = ();
  my $coltime;
  my $date;
  my $currdate = "x";

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];

    if( $oWkS->{Name} !~ /PE FEED/ ){
      progress( "CNBCEuro: $chd->{xmltvid}: Skipping worksheet: $oWkS->{Name}" );
      next;
    }

    progress( "CNBCEuro: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

    # browse through rows
    for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {

      my $colname;
      my $title;
      my $time;

      # the name of the column
      # is in the first row
      if( ! $colname ){
        my $oWkC = $oWkS->{Cells}[0][$iC];
        next if( ! $oWkC );
        my $colname = $oWkC->Value;

        next if( $colname !~ /^(CET|MONDAY|TUESDAY|WEDNESDAY|THURSDAY|FRIDAY|SATURDAY|SUNDAY)$/ );
        if( $colname =~ /CET/ ){
          $coltime = $iC;
          progress( "CNBCEuro: $chd->{xmltvid}: Using time from column no $coltime - $colname" );
        }
      }

      # browse through rows
      # start at row 1
      for(my $iR = 1 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

        my $oWkC = $oWkS->{Cells}[$iR][$iC];
        next if( ! $oWkC );
        my $text = $oWkC->Value;
#print ">$text<\n";

        next if( ! $text );

        if( isDate( $text ) ){

          $date = ParseDate( $text );

          if( $date ) {

            progress( "CNBCEuro: $chd->{xmltvid}: Date is $date" );

            if( $date ne $currdate ) {

              if( $currdate ne "x" ){
                $dsh->EndBatch( 1 );
              }

              my $batch_id = "${xmltvid}_" . $date;
              $dsh->StartBatch( $batch_id, $channel_id );
              $dsh->StartDate( $date , "00:00" );
              $currdate = $date;
            }
          }
        }

        # if this is the first line of the title
        # then read the time from the $coltime
        if( $text and ( $title eq "" ) ){
          $oWkC = $oWkS->{Cells}[$iR][$coltime];
          next if( ! $oWkC );
          $time = ParseTime( $oWkC->Value );
          next if( ! $time );
        }

        # we have to detect the change in color
        # of the top and bottom border line of a cell
        # if we have detected it -> we have the cell that has to be saved
        if($oWkC->{Format}) {

          my $topCol = $oWkC->{Format}->{BdrColor}[2];
          my $botCol = $oWkC->{Format}->{BdrColor}[3];

          if( $topCol and $title ){

            progress( "CNBCEuro: $chd->{xmltvid}: $time - $title" );

            # save the last cell
            my $ce = {
              channel_id => $channel_id,
              start_time => $time,
              title => $title,
            };

            $dsh->AddProgramme( $ce );

            $title = "";
          }

          # add the text to current title string
          $title .= " " . $text;
          $title = norm( $title );

          if( $botCol and $title ){

            progress( "CNBCEuro: $chd->{xmltvid}: $time - $title" );

            # save the cell
            my $ce = {
              channel_id => $channel_id,
              start_time => $time,
              title => $title,
            };

            $dsh->AddProgramme( $ce );

            $title = "";
          }
        }

      } # next row

      $colname = "";

    } # next column





  } # next worksheet

  $dsh->EndBatch( 1 );

  return;
}

sub isDate {
  my ( $text ) = @_;

  # format '7th June'
  if( $text =~ /^\d+(st|nd|th)\s+(january|february|march|april|may|june|july|august|september|october|novenber|december)$/i){
    return 1;
  }

  return 0;
}

sub ParseDate
{
  my ( $text ) = @_;

  # format '7th July'
  my( $day, $monthname ) = ( $text =~ /^(\d+)\S*\s+(\S+)$/ );

  return undef if( ! $day );

  my $month = MonthNumber( $monthname, 'en' );

  my $year = DateTime->today->year();

  my $date = sprintf( "%04d-%02d-%02d", $year, $month, $day );
  return $date;
}

sub ParseTime
{
  my ( $text ) = @_;

  my( $hour, $min ) = ( $text =~ /(\d{2})(\d{2})/ );

  return undef if( ! $hour or ! $min );

  return sprintf( "%02d:%02d", $hour, $min );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
