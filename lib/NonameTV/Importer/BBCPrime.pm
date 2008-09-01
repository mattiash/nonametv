package NonameTV::Importer::BBCPrime;

use strict;
use warnings;

=pod

Import data from xml-files that we download via FTP. Use BaseFile as
ancestor to avoid redownloading and reprocessing the files each time.

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;
use Data::Dumper;
use File::Temp qw/tempfile/;

use NonameTV qw/MyGet norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error 
                     log_to_string log_to_string_result/;

use NonameTV::Config qw/ReadConfig/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  $self->{grabber_name} = "BBCPrime";

  defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";
  
  my $conf = ReadConfig();
  $self->{FileStore} = $conf->{FileStore};

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile
{
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my $currdate = "x";

  progress( "FOX: $channel_xmltvid: Processing $file" );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  if( not defined( $oBook ) ) {
    error( "FOX: $file: Failed to parse xls" );
    return;
  }

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress("FOX: $channel_xmltvid: processing worksheet named '$oWkS->{Name}'");

    # read the rows with data
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      my $oWkC;

      # PROGRAMME - column 1
      $oWkC = $oWkS->{Cells}[$iR][1];
      next if( ! $oWkC );
      my $title = $oWkC->Value;
      if( $title =~ /FLOG IT/i ){
        next;
      }

      # DATETIME - column 0
      $oWkC = $oWkS->{Cells}[$iR][0];
      next if( ! $oWkC );
      my $datetime = $oWkC->Value;

      my $starttime = create_dt( $datetime );
      next if not $starttime;

      my $date = $starttime->ymd("-");

      if( $date ne $currdate ) {
        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $channel_xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;

        progress("FOX: $channel_xmltvid: Date is: $date");
      }

      # SRS - column 2
      $oWkC = $oWkS->{Cells}[$iR][2];
      my $srs = $oWkC->Value if $oWkC;

      # EP - column 3
      $oWkC = $oWkS->{Cells}[$iR][3];
      my $ep = $oWkC->Value if $oWkC;

      # EPISODE TITLE - column 4
      $oWkC = $oWkS->{Cells}[$iR][4];
      my $episodetitle = $oWkC->Value if $oWkC;

      # BILLING - column 5
      $oWkC = $oWkS->{Cells}[$iR][5];
      my $description = $oWkC->Value if $oWkC;

      # GENRE - column 6
      $oWkC = $oWkS->{Cells}[$iR][6];
      my $genre = $oWkC->Value if $oWkC;

      # RPT - column 7
      $oWkC = $oWkS->{Cells}[$iR][7];
      my $rpt = $oWkC->Value if $oWkC;

      # SUBS - column 8
      $oWkC = $oWkS->{Cells}[$iR][8];
      my $subs = $oWkC->Value if $oWkC;

      # CERT - column 9
      $oWkC = $oWkS->{Cells}[$iR][9];
      my $cert = $oWkC->Value if $oWkC;

      progress( "BBCPrime: $channel_xmltvid: $starttime - $title" );

      my $ce = {
        channel_id => $channel_id,
        title => $title,
        start_time => $starttime->hms(":"),
      };

      if( $ep ){
        $ce->{episode} = sprintf( ". %d .", $ep-1 );
      }

      if( $episodetitle ){
        $ce->{subtitle} = $episodetitle;
      }

      if( $description ){
        $ce->{description} = $description;
      }

      if( $genre ){
        #my($program_type, $category ) = $ds->LookupCat( 'BBCPrime', $genre );
        #AddCategory( $ce, $program_type, $category );
      }

      if( $cert ){
        $ce->{rating} = $cert;
      }

      $dsh->AddProgramme( $ce );

    } # next row

  } # next worksheet

  $dsh->EndBatch( 1 );

  return;
}

sub create_dt {
  my( $text ) = @_;

  my( $day, $month, $year, $hour, $min );

  if( $text =~ /^\d+\/\d+\/\d+\s+\d+\:\d+$/ ){
    ( $day, $month, $year, $hour, $min ) = ( $text =~ /^(\d+)\/(\d+)\/(\d+)\s+(\d+)\:(\d+)$/ );
  } else {
    return undef;
  }

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $min,
                          second => 0,
                          time_zone => 'Europe/Zagreb',
                          );

  return $dt;
}

sub UpdateFiles {
  my( $self ) = @_;

  foreach my $data ( @{$self->ListChannels()} ) { 
    my $filename = $data->{grabber_info};
    my $xmltvid = $data->{xmltvid};

    my $url = $self->{UrlRoot} . '/' . $data->{grabber_info};
    progress("BBCPrime: Fetching data from $url");

    http_get( $url, $self->{FileStore} . '/' . $xmltvid . '/' . $filename );
  }  
}

sub http_get {
  my( $url, $file ) = @_;

  qx[curl -s -S -z "$file" -o "$file" "$url"];
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
