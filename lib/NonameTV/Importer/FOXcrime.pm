package NonameTV::Importer::FOXcrime;

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
#use NonameTV qw/AddCategory norm/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  $self->{grabber_name} = "FOXcrime";

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;
  my( $time_slot, $etime );
  my( $en_title, $cro_title , $genre );
  my( $start_dt, $end_dt );
  my( $date, $firstdate , $lastdate );
  my( $oBook, $oWkS, $oWkC );

  progress( "FOXcrime: Processing $file" );
  
  $self->{fileerror} = 0;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;

  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  # the date is to be extracted from file name
  ( $firstdate , $lastdate ) = ParseDates( $file );
  $date = $firstdate;

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];

    progress( "FOXcrime: Processing worksheet: $oWkS->{Name} - $date" );

    my $batch_id = $xmltvid . "_" . $date;
    $ds->StartBatch( $batch_id , $channel_id );

    #for($iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
    for(my $iR = 1 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

#print "5\n";
      # Time Slot
      $oWkC = $oWkS->{Cells}[$iR][0];
      if( $oWkC ){
        $time_slot = $oWkC->Value;
#print "time_slot $time_slot\n";
      }

#print "6 $time_slot\n";
      if( $time_slot ){
        $etime = $time_slot;
#print "etime $etime\n";
        $end_dt = $self->to_utc( $date, $etime );
#print "end_dt $end_dt\n";
      } else {
        $end_dt = $start_dt->clone->add( hours => 2 );
      }
#print "7\n";

      # NOTICE: we miss the last show of the day

      # now after we got the next time_slot
      # we do the update
#print "$start_dt\n";
#print "$end_dt\n";
#print "8\n";
      if( defined($start_dt) and defined($end_dt) ) {

#        $etime =~ s/^(\d+:\d+).*/$1/;

        #$end_dt = $self->to_utc( $date, $etime );

#print "9\n";
        if( $start_dt gt $end_dt ) {
          $end_dt->add( days => 1 );
        }
#print "A\n";

        #progress( "FOXcrime: from $start_dt to $end_dt : $cro_title" );

        my $ce = {
          channel_id => $channel_id,
          title => $cro_title,
          subtitle => $en_title,
          start_time => $start_dt->ymd('-') . " " . $start_dt->hms(':'),
          end_time => $end_dt->ymd('-') . " " . $end_dt->hms(':'),
        };
    
        my($program_type, $category ) = $ds->LookupCat( "FOXcrime", $genre );
        #AddCategory( $ce, $program_type, $category );

        $ds->AddProgramme( $ce );
#print "--------\n";

      }

      # save the current endtime as the start
      # of the next show
      $start_dt = $end_dt;
#print "start_dt: $start_dt\n";
#print "1\n";

      # EN Title
      $oWkC = $oWkS->{Cells}[$iR][1];
      if( $oWkC ){
        $en_title = $oWkC->Value;
print "en_title: $en_title\n";
      }

#print "2\n";
      # Croatian Title
      $oWkC = $oWkS->{Cells}[$iR][2];
      if( $oWkC ){
        $cro_title = $oWkC->Value;
#print "cro_title: $cro_title\n";
      }
#print "3\n";

      # Genre
      $oWkC = $oWkS->{Cells}[$iR][3];
      if( $oWkC ){
        $genre = $oWkC->Value;
#print "genre: $genre\n";
      }
#print "4\n";

    } # next show

    #
    # increment the date we are processing
    #
    my $dt = ParseDate( $date );
    $dt->add( days => 1 );
    $date = $dt->ymd("-");

    $ds->EndBatch( 1 );

  } # next worksheet

  return;
}

sub ParseDate {
  my( $text ) = @_;

  my( $year, $month, $day ) = split( '-', $text );

  my $dt = DateTime->new(
			 year => $year,
			 month => $month,
			 day => $day );

  return $dt;
}

sub FindWeek {
  my( $text ) = @_;

  my $dt = ParseDate( $text );

  my( $week_year, $week_num ) = $dt->week;

  return "$week_year-$week_num";
}

sub ParseDates {
  my( $fname ) = @_;

  my $mnumb;

print "$fname\n";
  my $year = DateTime->today->year();

  my( $fday , $lday ) = ($fname =~ m/(\d+)/g );
print "$fday $lday\n";

  my $mname = $fname;
  $mname =~ s/.* (\d+) - (\d+) //;
  $mname =~ s/ .*//;
print "$mname\n";

  if( $fname =~ /December/ ){
    $mnumb = 12;
  }

  return( $year."-".$mnumb."-".$fday , $year."-".$mnumb."-".$lday );
}

sub to_utc {
  my $self = shift;
  my( $date, $time ) = @_;

  my( $year, $month, $day ) = split( '-', $date );
  my( $hour, $minute ) = split( ":", $time );

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          time_zone => 'Europe/Zagreb',
                          );
  
  $dt->set_time_zone( "UTC" );
  
  return $dt;
}
  
1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
