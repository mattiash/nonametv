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

use NonameTV qw/AddCategory norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);


  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  my( $oBook, $oWkS, $oWkC );

  $self->{fileerror} = 0;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  # Only process .xls files
  return if $file !~  /\.xls$/i;
  progress( "NetTV: Processing $file" );
  
  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  my $kada;
  my $batch_id;
  my $currdate = "x";
  my( $day, $month , $year , $hour , $min );
  my( $title, $premiere );

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];

    # process only the sheet with the name PPxle
    next if ( $oWkS->{Name} !~ /PPxle/ );

    progress( "NetTV: Processing worksheet: $oWkS->{Name}" );

    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
    #for(my $iR = 1 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # Time Slot
      $oWkC = $oWkS->{Cells}[$iR][0];
      if( $oWkC ){
        $kada = $oWkC->Value;
      }

      # next if kada is empty
      next if ( ! $kada );

      # check if date or time is in the first column
      if( $kada =~ /^\d\d\.\d\d\.\d\d$/ ){ # row with the date
        ( $day , $month , $year ) = ( $kada =~ /(\d\d)\.(\d\d)\.(\d\d)/ );
        $year += 2000;
      } elsif ( $kada =~ /^\d\d\.\d\d$/ ){ # row with the time of the show
        ( $hour , $min ) = ( $kada =~ /(\d\d)\.(\d\d)/ );
      } else {
        next;
      }

      next if( ! $day );
      next if( ! $hour );

      my $starttime = create_dt( $day , $month , $year , $hour , $min );
      my $date = $starttime->ymd('-');

      if( $date ne $currdate ) {
        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;
      }

      # Title
      $oWkC = $oWkS->{Cells}[$iR][1];
      if( $oWkC ){
        $title = $oWkC->Value;
      }
      next if( ! $title );

      # Genre
      my $genre = undef;
      $oWkC = $oWkS->{Cells}[$iR][2];
      if( $oWkC ){
        $genre = $oWkC->Value;
      }

      # Episode
      my $episode = undef;
      $oWkC = $oWkS->{Cells}[$iR][3];
      if( $oWkC ){
        $episode = $oWkC->Value;
      }

      # Premiere
      $oWkC = $oWkS->{Cells}[$iR][4];
      if( $oWkC ){
        $premiere = $oWkC->Value;
      }

      progress( "NetTV: $xmltvid: $starttime - $title" );

      my $ce = {
        channel_id => $channel_id,
        start_time => $starttime->hms(':'),
        title => $title,
      };

      # episode number
      my $ep = undef;
      if( $episode ){
         if( $episode =~ /^\d+\/\d+$/ ){
           my( $ep_nr, $ep_se ) = ( $episode =~ /(\d+)\/(\d+)/ );
           $ep = sprintf( "%d . %d .", $ep_se-1, $ep_nr-1 );
         } elsif( $episode =~ /^\d+$/ ){
           $ep = sprintf( ". %d .", $episode-1 );
         }
      }

      if( defined( $ep ) and ($ep =~ /\S/) ){
        $ce->{episode} = norm($ep);
        $ce->{program_type} = 'series';
      }

      if( $genre ){
        my( $program_type, $category ) = $ds->LookupCat( "NetTV", $genre );
        AddCategory( $ce, $program_type, $category );
      }

      $dsh->AddProgramme( $ce );

      $hour = undef;

    } # next row (next show)

    $dsh->EndBatch( 1 );

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
  #$dt->set_time_zone( "UTC" );

  return( $dt );
}
  
1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
