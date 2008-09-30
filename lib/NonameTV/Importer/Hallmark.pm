package NonameTV::Importer::Hallmark;

use strict;
use warnings;

=pod

Import data from Excel files delivered via e-mail.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;
use File::Temp qw/tempfile/;

use NonameTV qw/norm AddCategory MonthNumber/;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  $self->{grabber_name} = "Hallmark";

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $ds = $self->{datastore};

  # Only process .xls files.
  return if( $file !~ /\.xls$/i );
  progress( "Hallmark: $xmltvid: Processing $file" );

  my %columns = ();
  my $date;
  my $currdate = "x";


  my $batch_id = $xmltvid . "_" . $file;
  $ds->StartBatch( $batch_id , $channel_id );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress( "Hallmark: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

    # browse through rows
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # get the names of the columns from the 1st row
      if( not %columns ){
        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          $columns{norm($oWkS->{Cells}[$iR][$iC]->Value)} = $iC;
        }
        next;
      }
#foreach my $col (%columns) {
#print "$col\n";
#}

      # date - column 0 ('Date')
      my $oWkC = $oWkS->{Cells}[$iR][$columns{'Date'}];
      next if( ! $oWkC );

      $date = ParseDate( $oWkC->Value );
      next if( ! $date );

      # starttime - column ('Start')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Start'}];
      next if( ! $oWkC );
      my $starttime = create_dt( $date , $oWkC->Value ) if( $oWkC->Value );

      # endtime - column ('End')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'End'}];
      next if( ! $oWkC );
      my $endtime = create_dt( $date , $oWkC->Value ) if( $oWkC->Value );

      # title - column ('Title')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Title'}];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );

      my $type = $oWkS->{Cells}[$iR][$columns{'Type'}]->Value if $oWkS->{Cells}[$iR][$columns{'Type'}];
      my $prodno = $oWkS->{Cells}[$iR][$columns{'Prod No.'}]->Value if $oWkS->{Cells}[$iR][$columns{'Prod No.'}];
      my $episodetitle = $oWkS->{Cells}[$iR][$columns{'Episode Title'}]->Value if $oWkS->{Cells}[$iR][$columns{'Episode Title'}];
      my $slotlen = $oWkS->{Cells}[$iR][$columns{'Slot Len'}]->Value if $oWkS->{Cells}[$iR][$columns{'Slot Len'}];
      my $epino = $oWkS->{Cells}[$iR][$columns{'Epi No.'}]->Value if $oWkS->{Cells}[$iR][$columns{'Epi No.'}];
      my $cert = $oWkS->{Cells}[$iR][$columns{'Cert'}]->Value if $oWkS->{Cells}[$iR][$columns{'Cert'}];
      my $genre = $oWkS->{Cells}[$iR][$columns{'Genre'}]->Value if $oWkS->{Cells}[$iR][$columns{'Genre'}];
      my $year = $oWkS->{Cells}[$iR][$columns{'Year'}]->Value if $oWkS->{Cells}[$iR][$columns{'Year'}];
      my $director = $oWkS->{Cells}[$iR][$columns{'Director'}]->Value if $oWkS->{Cells}[$iR][$columns{'Director'}];
      my $actor = $oWkS->{Cells}[$iR][$columns{'Actor'}]->Value if $oWkS->{Cells}[$iR][$columns{'Actor'}];
      my $episodesynopsis = $oWkS->{Cells}[$iR][$columns{'Episode Synopsis'}]->Value if $oWkS->{Cells}[$iR][$columns{'Episode Synopsis'}];
      my $minisynopsis = $oWkS->{Cells}[$iR][$columns{'Mini Synopsis'}]->Value if $oWkS->{Cells}[$iR][$columns{'Mini Synopsis'}];
      my $synopsis = $oWkS->{Cells}[$iR][$columns{'Synopsis'}]->Value if $oWkS->{Cells}[$iR][$columns{'Synopsis'}];

      progress("Hallmark: $xmltvid: $starttime - $title");

      my $ce = {
        channel_id   => $channel_id,
        start_time   => $starttime->ymd("-") . " " . $starttime->hms(":"),
        end_time     => $endtime->ymd("-") . " " . $endtime->hms(":"),
        title        => $title,
      };

      # subtitle
      if( $episodetitle ){
        $ce->{subtitle} = $episodetitle;
      }

      # description
      if( $synopsis ){
        $ce->{description} = $synopsis;
      }

      # episode
      if( $epino ){
        $ce->{episode} = sprintf( ". %d .", $epino-1 );
        $ce->{program_type} = 'series';
      }

      # type
      if( $type ){
        $ce->{program_type} = $type;
      }

      # genre
      if( $genre ){
        my($program_type, $category ) = $ds->LookupCat( "Hallmark_genre", $genre );
        AddCategory( $ce, $program_type, $category );
      }

      # production year
      if( $year ){
        $ce->{production_date} = "$year-01-01";
      }

      # directors
      if( $director ){
        $ce->{directors} = $director;
      }

      # actors
      if( $actor ){
        $ce->{actors} = $actor;
      }

      $ds->AddProgramme( $ce );
    }

    %columns = ();

  }

  $ds->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my ( $dinfo ) = @_;

  my( $day, $monthname, $year );

  # format '033 03 Jul 2008'
  if( $dinfo =~ /^\d+\s+\d+\s+\S+\s+\d+$/ ){
    ( $day, $monthname, $year ) = ( $dinfo =~ /^\d+\s+(\d+)\s+(\S+)\s+(\d+)$/ );

  # format '05-sep-08'
  } elsif( $dinfo =~ /^\d+-(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)-\d+$/i ){
    ( $day, $monthname, $year ) = ( $dinfo =~ /^(\d+)-(\S+)-(\d+)$/ );
  }

  else {
    return undef;
  }

  return undef if( ! $year);

  $year+= 2000 if $year< 100;

  my $mon = MonthNumber( $monthname, "en" );

#print "DAY: $day\n";
#print "MON: $mon\n";
#print "YEA: $year\n";

  my $dt = DateTime->new( year   => $year,
                          month  => $mon,
                          day    => $day,
                          hour   => 0,
                          minute => 0,
                          second => 0,
                          time_zone => 'Europe/Zagreb',
                          );

  $dt->set_time_zone( "UTC" );

  return $dt;
}

sub create_dt
{
  my( $date, $time ) = @_;

  my( $hour, $min, $sec ) = ( $time =~ /(\d{2}):(\d{2}):(\d{2})/ );

  my $dt = $date->clone()->add( hours => $hour , minutes => $min , seconds => $sec );

  return $dt;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
