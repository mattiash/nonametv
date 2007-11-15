package NonameTV::Importer::FOXlife;

use strict;
use warnings;

=pod

Import data from Excel-files delivered via e-mail.  Each day
is handled as a separate batch.

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

  $self->{grabber_name} = "FOXlife";

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;
  my( $time_slot, $etime );
  my( $en_title, $cro_title );
  my( $start_dt, $end_dt );

  progress( "FOXlife: Processing $file" );
  
  $self->{fileerror} = 0;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );
  my($iR, $oWkS, $oWkC);

  # the date is to be extracted from file name
  my $firstdate = FirstDate( $file );
  my $date = $firstdate;

  my $batch_id = $xmltvid . "_" . FindWeek( $firstdate );
  $ds->StartBatch( $batch_id , $channel_id );

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];

    progress( "FOXlife: Processing worksheet: $oWkS->{Name}" );

    # one day per sheet
    #my $date = SheetDate( $firstdate , $iSheet );
#print "DATUM($iSheet): $date\n";

    for(my $iR = $oWkS->{MinRow}+1 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # Time Slot
      $oWkC = $oWkS->{Cells}[$iR][0];
      $time_slot = $oWkC->Value;
#print "time_slot $time_slot\n";

      $etime = $time_slot;
#print "etime $etime\n";
      $end_dt = $self->to_utc( $date, $etime );

      # NOTICE: we miss the last show of the day

      # now after we got the next time_slot
      # we do the update
      if( defined($start_dt) and defined($end_dt) ) {

        $etime =~ s/^(\d+:\d+).*/$1/;

        #$end_dt = $self->to_utc( $date, $etime );

        if( $start_dt gt $end_dt ) {
          $end_dt = $end_dt->add( days => 1 );
        }
print "end_dt: $end_dt\n";

        progress( "FOXlife: from $start_dt to $end_dt : $en_title" );

        my $ce = {
          channel_id => $channel_id,
          title => $cro_title,
          subtitle => $en_title,
          start_time => $start_dt->ymd('-') . " " . $start_dt->hms(':'),
          end_time => $end_dt->ymd('-') . " " . $end_dt->hms(':'),
        };
    
        $ds->AddProgramme( $ce );

      }

      # save the current endtime as the start
      # of the next show
      $start_dt = $end_dt;
print "start_dt: $start_dt\n";

      # EN Title
      $en_title = $oWkS->{Cells}[$iR][1]->Value;
#print "en_title: $en_title\n";

      # Croatian Title
      $cro_title = $oWkS->{Cells}[$iR][2]->Value;
#print "cro_title: $cro_title\n";

    }

  } # next worksheet

  $ds->EndBatch( 1 );

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

sub FirstDate {
  my( $fname ) = @_;

  #print DateTime->today->year() . "\n";

  return "2007-11-16";
}

sub SheetDate {
  my( $first , $off ) = @_;

  return $first;
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
