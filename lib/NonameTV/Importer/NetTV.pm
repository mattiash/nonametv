package NonameTV::Importer::NetTV;

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

  $self->{grabber_name} = "NetTV";

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;
  my( $kada, $newtime, $lasttime );
  my( $title, $genre , $episode , $premiere );
  my( $day, $month , $year , $hour , $min );
  my( $oBook, $oWkS, $oWkC );

  # Only process .xls files.
  return if $file !~  /\.xls$/i;

  progress( "NetTV: Processing $file" );
  
  $self->{fileerror} = 0;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;

  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];

    # process only the sheet with the name PPxle
    next if ( $oWkS->{Name} !~ /PPxle/ );

    progress( "NetTV: Processing worksheet: $oWkS->{Name}" );

    my $batch_id = $xmltvid . "_" . $file;
    $ds->StartBatch( $batch_id , $channel_id );

    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
    #for(my $iR = 1 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # Time Slot
      $oWkC = $oWkS->{Cells}[$iR][0];
      if( $oWkC ){
        $kada = $oWkC->Value;
      }

      # next if kada is empty
      next if ( ! $kada );
      next if( $kada !~ /\S.*\S/ );

      # count number of dots in a string
      my $count = ($kada =~ tr/\.//);
      if ( $count == 2 ){	# row with the date

        ( $day , $month , $year ) = split( '\.' , $kada );
        $year += 2000;

      } elsif ( $count == 1 ){	# row with the time of the show

        ( $hour , $min ) = split( '\.' , $kada );

      } else {
        next;
      }

      next if( ! $day );
      next if( ! $hour );

      $newtime = create_dt( $day , $month , $year , $hour , $min );

      if( defined( $lasttime ) and defined( $newtime ) ){

        if( $newtime < $lasttime ){
          $newtime->add( days => 1 );
        }
#        progress("NetTV: $lasttime - $newtime : $title");

        my $ce = {
          channel_id   => $channel_id,
          start_time   => $lasttime->ymd("-") . " " . $lasttime->hms(":"),
          end_time     => $newtime->ymd("-") . " " . $newtime->hms(":"),
          title        => $title,
        };

#        if( defined( $episode ) )
#        {
#          $ce->{episode} = norm($episode);
#          #$ce->{program_type} = 'series';
#        }

        if( defined( $genre ) and $genre =~ /\S/ )
        {
          my( $program_type, $category ) = $ds->LookupCat( "NetTV", $genre );
          #AddCategory( $ce, $program_type, $category );
        }

        $ds->AddProgramme( $ce );
      }

      # Title
      $oWkC = $oWkS->{Cells}[$iR][1];
      if( $oWkC ){
        $title = $oWkC->Value;
      }

      # Genre
      $oWkC = $oWkS->{Cells}[$iR][2];
      if( $oWkC ){
        $genre = $oWkC->Value;
      }

      # Episode
      $oWkC = $oWkS->{Cells}[$iR][3];
      if( $oWkC ){
        $episode = $oWkC->Value;
      }

      # Premiere
      $oWkC = $oWkS->{Cells}[$iR][4];
      if( $oWkC ){
        $premiere = $oWkC->Value;
      }

      if( defined( $newtime ) ){
        $lasttime = $newtime;
      }

    } # next row (next show)

    $ds->EndBatch( 1 );

  } # next worksheet

  return;
}

sub create_dt
{
  my ( $dy , $mo , $yr , $hr , $mn ) = @_;

  my $dt = DateTime->new( year   => $yr,
                           month  => $mo,
                           day    => $dy,
                           hour   => $hr,
                           minute => $mn,
                           second => 0,
                           time_zone => 'Europe/Zagreb',
                           );

  # times are in CET timezone in original XLS file
  $dt->set_time_zone( "UTC" );

  return( $dt );
}
  
1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
