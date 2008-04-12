package NonameTV::Importer::FOX;

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
use NonameTV qw/AddCategory/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  $self->{grabber_name} = "FOX";

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

  progress( "FOX: Processing $file" );
  
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

    progress( "FOX: Processing worksheet: $oWkS->{Name} - $date" );

    my $batch_id = $xmltvid . "_" . $date;
    $ds->StartBatch( $batch_id , $channel_id );

    #for($iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
    for(my $iR = 1 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # Time Slot
      $oWkC = $oWkS->{Cells}[$iR][0];
      if( $oWkC ){
        $time_slot = $oWkC->Value;
      }

      if( $time_slot ){
        $etime = $time_slot;
        $end_dt = $self->to_utc( $date, $etime );
      } else {
        $end_dt = $start_dt->clone->add( hours => 2 );
      }

      # NOTICE: we miss the last show of the day

      # now after we got the next time_slot
      # we do the update
      if( defined($start_dt) and defined($end_dt) and $cro_title ) {

        #$end_dt = $self->to_utc( $date, $etime );

        if( $start_dt gt $end_dt ) {
          $end_dt->add( days => 1 );
        }

        progress( "FOX: from $start_dt to $end_dt : $en_title" );

        my $ce = {
          channel_id => $channel_id,
          title => $cro_title,
          subtitle => $en_title,
          start_time => $start_dt->ymd('-') . " " . $start_dt->hms(':'),
          end_time => $end_dt->ymd('-') . " " . $end_dt->hms(':'),
        };
    
        if( $genre ){
          my($program_type, $category ) = $ds->LookupCat( 'FOX', $genre );
          AddCategory( $ce, $program_type, $category );
        }

        $ds->AddProgramme( $ce );

      }

      # save the current endtime as the start
      # of the next show
      $start_dt = $end_dt;

      # EN Title
      $oWkC = $oWkS->{Cells}[$iR][1];
      if( $oWkC ){
        $en_title = $oWkC->Value;
      }

      # Croatian Title
      $oWkC = $oWkS->{Cells}[$iR][2];
      if( $oWkC ){
        $cro_title = $oWkC->Value;
      }

      # Genre
      $oWkC = $oWkS->{Cells}[$iR][3];
      if( $oWkC ){
        $genre = $oWkC->Value;
      }

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

  my $year = DateTime->today->year();

  my( $fday , $lday ) = ($fname =~ m/(\d+)/g );

  my $mname = $fname;
  $mname =~ s/.* (\d+) - (\d+) //;
  $mname =~ s/ .*//;

  $year = 2008;

  if( $fname =~ /January/ or $fname =~ /Jan/ ){
    $mnumb = 1;
  } elsif( $fname =~ /February/ or $fname =~ /Feb/ ){
    $mnumb = 2;
  } elsif( $fname =~ /March/ or $fname =~ /Mar/ ){
    $mnumb = 3;
  } elsif( $fname =~ /April/ or $fname =~ /Apr/ ){
    $mnumb = 4;
  } elsif( $fname =~ /May/ or $fname =~ /May/ ){
    $mnumb = 5;
  } elsif( $fname =~ /June/ or $fname =~ /Jun/ ){
    $mnumb = 6;
  } elsif( $fname =~ /July/ or $fname =~ /Jul/ ){
    $mnumb = 7;
  } elsif( $fname =~ /August/ or $fname =~ /Aug/ ){
    $mnumb = 8;
  } elsif( $fname =~ /September/ or $fname =~ /Sep/ ){
    $mnumb = 9;
  } elsif( $fname =~ /October/ or $fname =~ /Oct/ ){
    $mnumb = 10;
  } elsif( $fname =~ /November/ or $fname =~ /Nov/ ){
    $mnumb = 11;
  } elsif( $fname =~ /December/ or $fname =~ /Dec/ ){
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
