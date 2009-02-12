package NonameTV::Importer::Trace;

use strict;
use warnings;

=pod

Import data from xls files delivered via e-mail.

Channel: www.trace.tv

=cut

use utf8;

use DateTime;
use Encode qw/encode decode/;
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

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Zagreb" );
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

  progress( "Trace XLS: $channel_xmltvid: Processing XLS $file" );

  my( $oBook, $oWkS, $oWkC );
  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  if( not defined( $oBook ) ) {
    error( "Trace XLS: $file: Failed to parse xls" );
    return;
  }

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];

    if( $oWkS->{Name} !~ /FROM GMT \+1 TO GMT\+2/ ){
      progress("Trace XLS: $channel_xmltvid: skipping worksheet named '$oWkS->{Name}'");
      next;
    }

    progress("Trace XLS: $channel_xmltvid: processing worksheet named '$oWkS->{Name}'");

    # read the rows with data
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      if( not %columns ){

        # the column names are stored in the 5th row
        # so read them and store their column positions
        # for further findvalue() calls
        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          if( $oWkS->{Cells}[$iR][$iC] ){
            $columns{$oWkS->{Cells}[$iR][$iC]->Value} = $iC;
          }
        }
#foreach my $cl (%columns) {
#print "$cl\n";
#}

        # the number of columns must be 8 or more
        if( keys( %columns ) < 8 ){
          undef %columns;
        }

        next;
      }
      
      # Date
      $oWkC = $oWkS->{Cells}[$iR][$columns{'programmeDate DD/MM/YY'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      $date = ParseDate( $oWkC->Value );
      next if( ! $date );

      if( $date ne $currdate ) {
        if( $currdate ne "x" ) {
	  $dsh->EndBatch( 1 );
        }

        my $batch_id = $channel_xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;

        progress("Trace XLS: $channel_xmltvid: Date is: $date");
      }

      # Time
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Programme Start Time'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $time = ParseTime( $oWkC->Value );
      next if( ! $time );

      # Title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'programmeName'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $title = $oWkC->Value;
      next if( ! $title );

      # Duration
      $oWkC = $oWkS->{Cells}[$iR][$columns{'programme Duration'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $duration = $oWkC->Value;

      # Synopsis
      $oWkC = $oWkS->{Cells}[$iR][$columns{'programme Synopsis Txt'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $synopsis = $oWkC->Value;

      # Rating
      $oWkC = $oWkS->{Cells}[$iR][$columns{'programme Rating'}];
      next if( ! $oWkC );
      my $rating = $oWkC->Value;

      # Language
      $oWkC = $oWkS->{Cells}[$iR][$columns{'programme Language'}];
      next if( ! $oWkC );
      my $language = $oWkC->Value;

      progress( "Trace XLS: $channel_xmltvid: $time - $title" );

      my $ce = {
        channel_id => $channel_id,
        title => $title,
        start_time => $time,
      };

      $ce->{description} = $synopsis if $synopsis;

      $dsh->AddProgramme( $ce );

    } # next row

    undef %columns;

  } # next worksheet

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my( $text ) = @_;

  return undef if not $text;

  # Format 'DD/MM/YY'
  my( $day, $month, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d+)$/ );

  $year += 2000 if $year < 100;

  return sprintf( "%04d-%02d-%02d", $year, $month, $day );
}

sub ParseTime
{
  my( $text ) = @_;

  return undef if not $text;

  my( $hour, $min, $sec );

  # Format '21:00'
  if( $text =~ /^\d+:\d+$/ ){
    ( $hour, $min ) = ( $text =~ /^(\d+):(\d+)$/ );
  }

  return sprintf( "%02d:%02d", $hour, $min );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
