package NonameTV::Importer::Jetix;

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

# File types
use constant {
  FT_UNKNOWN  => 0,  # unknown
  FT_FLATXLS  => 1,  # flat xls file
  FT_GRIDXLS  => 2,  # xls file with grid
};

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  $self->{grabber_name} = "Jetix";

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

  my $ft = CheckFileFormat( $file );

  if( $ft eq FT_FLATXLS ){
    $self->ImportFlatXLS( $file, $channel_id, $xmltvid );
  } else {
    error( "Jetix: $xmltvid: Unknown file format of $file" );
  }

  return;
}

sub CheckFileFormat
{
  my( $file ) = @_;

  # Only process .xls files.
  return if( $file !~ /\.xls$/i );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );
  return FT_UNKNOWN if( ! $oBook );

  # the flat sheet file which sometimes uses
  # Jetix Play has the single sheet and
  # column names in the first row
  # check against the name of the 3rd column value of the first row
  # the content of this column shoul be 'English Prog Title'
  if( $oBook->{SheetCount} eq 1 ){
    my $oWkS = $oBook->{Worksheet}[0];
    my $oWkC = $oWkS->{Cells}[0][2];
    if( $oWkC ){
      return FT_FLATXLS if( $oWkC->Value =~ /^English Prog Title$/ );
    }
  }

  return FT_UNKNOWN;
}

sub ImportFlatXLS
{
  my $self = shift;
  my( $file, $channel_id, $xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my %columns = ();
  my $date;
  my $currdate = "x";

  progress( "Jetix: $xmltvid: Processing FlatXLS $file" );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );
  if( not defined( $oBook ) ) {
    error( "Jetix: $file: Failed to parse xls" );
    return;
  }

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress("Jetix: $xmltvid: processing worksheet named '$oWkS->{Name}'");

    # read the rows with data
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {

          if( $oWkS->{Cells}[$iR][$iC] ){
            $columns{$oWkS->{Cells}[$iR][$iC]->Value} = $iC;

            # the name of the column 'GMT Time'
            # is sometimes '0 Time'
            if( $oWkS->{Cells}[$iR][$iC]->Value =~ /0 Time/ ){
              $columns{'GMT Time'} = $iC;
            }
          }
        }
#foreach my $cl (%columns) {
#print ">$cl<\n";
#}
        next;
      }

      # Date
      my $oWkC = $oWkS->{Cells}[$iR][$columns{'Date'}];
      next if( ! $oWkC );
      my $dateinfo = $oWkC->Value;
      next if( ! $dateinfo );

      # Time
      $oWkC = $oWkS->{Cells}[$iR][$columns{'GMT Time'}];
      next if( ! $oWkC );
      my $time = $oWkC->Value;
      next if( ! $time );

      # Title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'English Prog Title'}];
      next if( ! $oWkC );
      my $engtitle = $oWkC->Value;
      next if( ! $engtitle );

      # Episode title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'English Eps Title'}];
      next if( ! $oWkC );
      my $episodetitle = $oWkC->Value;

      # Program Synopsis
      $oWkC = $oWkS->{Cells}[$iR][$columns{'English Prog Synopsis'}];
      next if( ! $oWkC );
      my $synopsis = $oWkC->Value;

      # Genre
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Genre'}];
      next if( ! $oWkC );
      my $genre = $oWkC->Value;

      my $date = ParseDate( $dateinfo );

      if( $date ne $currdate ) {
        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }
        my $batch_id = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "03:00" );
        $currdate = $date;

        progress("Jetix: $xmltvid: Date is: $date");
      }

      progress( "Jetix XLS: $xmltvid: $time - $engtitle" );

      my $ce = {
        channel_id => $channel_id,
        title => $engtitle,
        start_time => $time,
      };

      $ce->{description} = $synopsis if $synopsis;

      if( $genre ){
        my($program_type, $category ) = $ds->LookupCat( 'Jetix', $genre );
        AddCategory( $ce, $program_type, $category );
      }

      $dsh->AddProgramme( $ce );

    } # next row

    %columns = ();

  } # next worksheet

  $dsh->EndBatch( 1 );

  return;
}


sub ImportGrid
{
  my $self = shift;
  my( $file, $channel_id, $xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  # Only process .xls files.
  return if( $file !~ /\.xls$/i );
  progress( "Jetix: $xmltvid: Processing $file" );

  my $coltime = 0;  # the time is in the column no. 0
  my $firstcol = 1;  # first column - monday
  my $lastcol = 7;  # last column - sunday
  my $firstrow = 4;  # schedules are starting from this row

  my @shows = ();
  my $firstdate;
  my $date;
  my $currdate = "x";

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress( "Jetix: $xmltvid: Processing worksheet: $oWkS->{Name}" );

    $firstdate = ParseFirstDate( $oWkS->{Name} );
    progress( "Jetix: $xmltvid: First date in the sheet is " . $firstdate->ymd("-") );

    # browse through columns
    for(my $iC = $firstcol ; $iC <= $lastcol ; $iC++) {

#print "kolona $iC\n";

      # browse through rows
      # start at row firstrow
      for(my $iR = $firstrow ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

        my $oWkC = $oWkS->{Cells}[$iR][$iC];
        next if( ! $oWkC );
        my $text = $oWkC->Value;
        next if( ! $text );
#print "$iR $iC >$text<\n";

        my $title = $text;

        # fetch the time from $coltime column
        $oWkC = $oWkS->{Cells}[$iR][$coltime];
        next if( ! $oWkC );
        my $time = $oWkC->Value;
        next if( ! $time );
        next if( $time =~ /^KEY$/ );
#print "$iR $iC >$time<\n";

        my $show = {
          start_time => $time,
          title => $title,
        };
        @{$shows[$iC]} = () if not $shows[$iC];
        push( @{$shows[$iC]} , $show );

        # find to how many columns this column spreads to the right
        # all these days have the same show at this time slot
        for( my $c = $iC + 1 ; $c <= $lastcol ; $c++) {
          $oWkC = $oWkS->{Cells}[$iR][$c];
          if( ! $oWkC->Value ){
#print "spread $c " . $show->{title} . "\n";
            @{$shows[$c]} = () if not $shows[$c];
            push( @{$shows[$c]} , $show );
          } else {
            last;
          }
        }


      } # next row
#print "zadnje u koloni $iC\n----------------\n";
    } # next column

  } # next worksheet

  # insert data to database
  for( my $i = 1 ; $i <= 7 ; $i++ ){
#print "DAN: $i\n";
    $date = SetDate( $firstdate , $i );

    if( $date ) {

      progress( "Jetix: $xmltvid: Date is " . $date->ymd("-") );

      if( $date ne $currdate ) {

        if( $currdate ne "x" ){
          $dsh->EndBatch( 1 );
        }

        my $batch_id = "${xmltvid}_" . $date->ymd("-");
        $dsh->StartBatch( $batch_id, $channel_id );
        $dsh->StartDate( $date->ymd("-") , "06:00" );
        $currdate = $date;
      }
    }

    foreach my $s ( @{$shows[$i]} ) {

      #progress( "Jetix: $xmltvid: $s->{start_time} - $s->{title}" );

      my $ce = {
        channel_id => $channel_id,
        start_time => $s->{start_time},
        title => $s->{title},
      };

      $dsh->AddProgramme( $ce );

    } # next show

  } # next day

  $dsh->EndBatch( 1 );

  return;
}

sub ParseFirstDate {
  my ( $text ) = @_;

#print ">$text<\n";
  my( $day, $monthname );

  # format '28th July - 3rd August'
  if( $text =~ /^\s*\d+(st|nd|rd|th)\s*\S+\s*-\d+(st|nd|rd|th)\s*\S+\s*$/i ){
#print "f1\n";
    ( $day, $monthname ) = ( $text =~ /^\s*(\d+)\S+\s*(\S+)\s*-\d+\S+\s*\S+/ );
  }
  # format '4th - 10th Aug'
  elsif( $text =~ /^\s*\d+(st|nd|rd|th)\s*-\s*\d+(st|nd|rd|th)\s+\S+\s*$/i ){
#print "f2\n";
    ( $day, $monthname ) = ( $text =~ /^\s*(\d+)\S+\s*-\s*\d+\S+\s+(\S+)\s*$/ );
  }
#print "DAY: $day\n";
#print "MON: $monthname\n";

  my $year = 2008;

  my $month = MonthNumber( $monthname , 'en' );

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => 0,
                          minute => 0,
                          second => 0,
                          time_zone => 'Europe/Zagreb',
                          );
  return $dt;
}

sub SetDate {
  my ( $first, $off ) = @_;

  my $d = $first->clone->add( days => ( $off - 1 ) );

  return $d;
}

sub ParseDate {
  my ( $text ) = @_;

  my( $day, $monthname, $year ) = ( $text =~ /^(\d+)-(\S+)-(\d+)$/ );

  my $month = MonthNumber( $monthname , 'en' );

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}


1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
