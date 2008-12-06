package NonameTV::Importer::WFC;

use strict;
use warnings;

=pod

Channels: World Fashion Channel (www.worldfashion.tv)

Import data from xls files delivered via e-mail.

Features:

=cut

use utf8;

use POSIX;
use DateTime;
use Spreadsheet::ParseExcel;

use NonameTV qw/norm AddCategory MonthNumber/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

# File types
 use constant {
   FT_UNKNOWN    => 0,  # unknown
   FT_SCHEMAXLS  => 1,  # weekly schema in xls
   FT_SCHEMADOC  => 2,  # weekly schema in doc
   FT_SCHEDULE   => 3,  # daily schedule in doc
};

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  $self->{grabber_name} = "WFC";

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

  if( $ft eq FT_SCHEMAXLS ){
    $self->ImportSchemaXLS( $file, $channel_id, $xmltvid );
  } else {
    error( "WFC: $xmltvid: Unknown file format of $file" );
  }

  return;
}

sub CheckFileFormat
{
  my( $file ) = @_;

  # check if the file name is in format 'Weekly program Schedule 1 December 2008.xls'
  if( $file =~ /Weekly program Schedule\s+\d+\s+(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d+\.xls$/i ){
    return FT_SCHEMAXLS;
  }

  return FT_UNKNOWN;
}

sub ImportSchemaXLS
{
  my $self = shift;
  my( $file, $channel_id, $xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  # Only process .xls files.
  return if( $file !~ /\.xls$/i );
  progress( "Jetix GridXLS: $xmltvid: Processing $file" );

  my $firstcol = 1;  # first column - monday
  my $lastcol = 13;  # last column - sunday
  my $firstrow = 2;  # schedules are starting from this row

  my( $dtstart, $firstdate, $lastdate ) = ParsePeriod( $file );
  progress( "Jetix GridXLS: $xmltvid: Importing data for period from " . $firstdate->ymd("-") . " to " . $lastdate->ymd("-") );
  my $period = $lastdate - $firstdate;
  my $spreadweeks = int( $period->delta_days / 7 ) + 1;
  if( $period->delta_days > 6 ){
    progress( "Jetix GridXLS: $xmltvid: Schedules scheme will spread accross $spreadweeks weeks" );
  }

  my @shows = ();

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];

    # check if the sheet is empty
    # the cell at position iR = 2, iC = 0 should contain time
    my $oWkC = $oWkS->{Cells}[2][0];
    next if( ! $oWkC );
    next if( ! $oWkC->Value );
    next if( $oWkC->Value !~ /^\d+:\d+$/ );

    progress( "Jetix GridXLS: $xmltvid: Processing worksheet: $oWkS->{Name}" );

    my $dayno = 0;

    # browse through columns
    for(my $iC = $firstcol ; $iC <= $lastcol ; $iC+=2 ){

      # browse through rows
      # start at row firstrow
      for(my $iR = $firstrow ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

        $oWkC = $oWkS->{Cells}[$iR][$iC];
        next if( ! $oWkC );
        my $text = $oWkC->Value;
        next if( ! $text );

        my $title = $text;

        # fetch the time from the previous column
        $oWkC = $oWkS->{Cells}[$iR][$iC-1];
        next if( ! $oWkC );
        my $time = $oWkC->Value;
        next if( ! $time );

        my $show = {
          start_time => $time,
          title => $title,
        };
        @{$shows[$dayno]} = () if not $shows[$dayno];
        push( @{$shows[$dayno]} , $show );

      } # next row

      $dayno++;

    } # next column

    if( $spreadweeks ){
      @shows = SpreadWeeks( $spreadweeks, @shows );
    }

    FlushData( $dsh, $dtstart, $firstdate, $lastdate, $channel_id, $xmltvid, @shows );

  } # next worksheet
}

sub ParsePeriod {
  my ( $text ) = @_;

  my @days = qw/Monday Tuesday Wednesday Thursday Friday Saturday Sunday/;

  # format 'Weekly program Schedule 1 December 2008.xls'
  my( $day, $monthname, $year ) = ( $text =~ /Weekly program Schedule\s+(\d+)\s+(january|february|march|april|may|june|july|august|september|october|november|december)\s+(\d+)\.xls$/i );

  if( not $monthname or not $year ){
    error("Error while parsing period from '$text'");
    return( undef, undef, undef );
  }

  my $month = MonthNumber( $monthname, "en" );

  my $firstdate = DateTime->new( year   => $year,
                                 month  => $month,
                                 day    => $day,
                                 hour   => 0,
                                 minute => 0,
                                 second => 0,
                                 time_zone => 'Europe/Zagreb',
  );

  # find the name of the first day of the month
  my $firstday = $firstdate->day_name;

  # find the name of the last day of the month
  my $lastdate = DateTime->last_day_of_month( year => $year, month => $month );

  # the schedules data is on weekly basis
  # find the offset, or how many days it spreads to previous month
  my $offset = -1;
  for( my $i = 0; $i < scalar(@days); $i++ ){
    if( $days[$i] eq $firstday ){
      $offset = $i;
    }
  }

  if( $offset eq -1 ){
    error("Can't determine day offset");
    return( undef, undef, undef );
  }

  # find the first date which can be covered by this schedule
  # we will skip later the dates not from the correct month
  my $dtstart = $firstdate->clone->subtract( days => $offset );

  return( $dtstart, $firstdate, $lastdate );
}

sub SpreadWeeks {
  my ( $spreadweeks, @shows ) = @_;

  for( my $w = 1; $w < $spreadweeks; $w++ ){
print "WEEK $w\n";
    for( my $d = 0; $d < 7; $d++ ){
      my @tmpshows = @{$shows[$d]};
      @{$shows[ ( $w * 7 ) + $d ]} = @tmpshows;
    }
  }

  return @shows;
}

sub FlushData {
  my ( $dsh, $dtstart, $firstdate, $lastdate, $channel_id, $xmltvid, @shows ) = @_;

  my $date = $dtstart;
  my $currdate = "x";

  my $batch_id = "${xmltvid}_schema_" . $firstdate->ymd("-");
  $dsh->StartBatch( $batch_id, $channel_id );

  # run through the shows
  foreach my $dayshows ( @shows ) {

    if( $date < $firstdate or $date > $lastdate ){
      progress( "WFC: $xmltvid: Date " . $date->ymd("-") . " is outside of the month " . $firstdate->month_name . " -> skipping" );
      $date->add( days => 1 );
      next;
    }

    progress( "WFC: $xmltvid: Date is " . $date->ymd("-") );

    if( $date ne $currdate ) {

      $dsh->StartDate( $date->ymd("-") , "06:00" );
      $currdate = $date->clone;

    }

    foreach my $s ( @{$dayshows} ) {

      progress( "WFC: $xmltvid: $s->{start_time} - $s->{title}" );

      my $ce = {
        channel_id => $channel_id,
        start_time => $s->{start_time},
        title => $s->{title},
      };

      $dsh->AddProgramme( $ce );

    } # next show in the day

    # increment the date
    $date->add( days => 1 );

  } # next day

  $dsh->EndBatch( 1 );

}

sub isDate {
  my ( $text ) = @_;

  # format 'ZA  PETAK  24.10.2008.'
  if( $text =~ /(ponedjeljak|utorak|srijeda|ČETVRTAK|petak|subota|nedjelja)\s+\d+\.\s*\d+\.\s*\d+\.*$/i ){
    return 1;
  }

  return 0;
}

sub ParseDate {
  my( $text ) = @_;

  my( $dayname, $day, $month, $year ) = ( $text =~ /(\S+)\s+(\d+)\.\s*(\d+)\.\s*(\d+)\.*$/ );

  $year += 2000 if $year lt 100;

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub isShow {
  my ( $text ) = @_;

  # format '15,30 Zap skola,  crtana serija  ( 3/52)'
  if( $text =~ /^\d+[\,|\:]\d+\s+\S+/i ){
    return 1;
  }

  return 0;
}

sub ParseShow {
  my( $text ) = @_;

  my( $hour, $min, $title, $genre );

#  if( $text =~ /\,.*/ ){
#    ( $genre ) = ( $text =~ /\,\s*(.*)$/ );
#    $text =~ s/\,.*//;
#  }

  ( $hour, $min, $title ) = ( $text =~ /^(\d+)[\,|\:](\d+)\s+(.*)$/ );

  return( $hour . ":" . $min , $title , $genre );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
