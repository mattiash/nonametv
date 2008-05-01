package NonameTV::Importer::FTV;

use strict;
use warnings;

=pod

Importer for data from FTV. 
One file per month downloaded from extreme.com site.
The downloaded file is in xls-format.

Features:

=cut

use POSIX qw/strftime/;
use DateTime;
use Spreadsheet::ParseExcel;

use NonameTV qw/MyGet norm AddCategory/;
use NonameTV::Log qw/info progress error logdie/;

use NonameTV::Importer::BaseOne;

use base 'NonameTV::Importer::BaseOne';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{grabber_name} = "FTV";

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    return $self;
}

sub ImportContent
{
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my( $stime , $etime );
  my( $start_dt , $end_dt );
  my( $program_title , $program_description );
  my( $genre );

  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse('/tmp/ftv.xls');

  my($iR, $oWkS, $oWkC);

  # There are few Worksheets in the xls file
  # the epg data can be found in the first one

  # The columns in the xls file are:
  # --------------------------------
  # date, time, program, description

  foreach my $oWkS (@{$oBook->{Worksheet}}) {

    progress("--------- SHEET: $oWkS->{Name}");

    if( $oWkS->{Name} !~ /EPG/ ){
      progress("Skipping sheet $oWkS->{Name}");
      next;
    }

    # start from row 2
    # the first row looks like one cell saying like "EPG DECEMBER 2007  (Yamal - HotBird)"
    # the 2nd row contains column names Date, Time (local), Progran, Description
    #for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
    for(my $iR = 2 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # schedule_date (column 0)
      $oWkC = $oWkS->{Cells}[$iR][0];
      my $schedule_date = $oWkC->Value;

      # start_time (column 1)
      $oWkC = $oWkS->{Cells}[$iR][1];
      my $start_time = $oWkC->Value;

      if( $start_time ){
        $etime = $start_time;
        $end_dt = $self->to_utc( $schedule_date, $etime );
      }

      if( $start_dt and $end_dt ){
        progress("$start_dt $end_dt $program_title");

        my $ce = {
          channel_id   => $chd->{id},
          title        => norm($program_title),
          description  => norm($program_description),
          start_time   => $start_dt->ymd("-") . " " . $start_dt->hms(":"),
          end_time     => $end_dt->ymd("-") . " " . $end_dt->hms(":"),
        };

        my($program_type, $category ) = $ds->LookupCat( "FTV", $genre );
        AddCategory( $ce, $program_type, $category );

        $ds->AddProgramme( $ce );
      }

      # the last time we red is the start time
      $start_dt = $end_dt->clone();

      # program_title (column 2)
      $oWkC = $oWkS->{Cells}[$iR][2];
      $program_title = $oWkC->Value;
      if( $program_title =~ /Midnight Hot/ ){ $genre = "erotic"; }
      elsif( $program_title =~ /F Hot/ ){ $genre = "erotic"; }
      elsif( $program_title =~ /Lingerie/ ){ $genre = "erotic"; }
      elsif( $program_title =~ /F Party/ ){ $genre = "magazine"; }
      else { $genre = ""; }

      # program_description (column 3)
      $oWkC = $oWkS->{Cells}[$iR][3];
      $program_description = $oWkC->Value;

    } # next row
  } # next worksheet

  unlink("/tmp/ftv.xls");

  # Success
  return 1;
}

sub to_utc
{
  my $self = shift;
  my( $dat , $tim ) = @_;

  my ( $month , $day , $year ) = split( "-" , $dat );
  my ( $hour , $minute ) = split( ":" , $tim );

  if( not defined $year )
  {
    return undef;
  }

  my $dt = DateTime->new( year   => 2000 + $year,
                           month  => $month,
                           day    => $day,
                           hour   => $hour,
                           minute => $minute,
                           second => 0,
                           time_zone => 'Europe/Zagreb',
                           );

  $dt->set_time_zone( "UTC" );

  return( $dt );
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my( $year, $week ) = ($batch_id =~ /_(\d+)-(\d+)/);

  # the url to fetch data from
  # is in the format http://www.ftv.com/bilder/d17/EPG_HotBird3-Yamal_December2007.xls
  # UrlRoot = http://www.ftv.com/bilder/d17/
  # GrabberInfo = EPG_HotBird3-Yamal_

  my $nowmonth = DateTime->today->month_name();
  my $nowyear = DateTime->today->year();

  #my $url = $self->{UrlRoot} . "/" . $data->{grabber_info} .  $nowmonth . "_" . $nowyear .  ".xls";
  #my $url = $self->{UrlRoot} . "/d18/" . "Grid_EPG_April_2008_HotBird-Yamal.xls";
  my $url = $self->{UrlRoot} . "/d18/" . "Grid-EPGMay_2008Hotbird-Yamal.xls";

  progress("Fetching xls file from $url");

  my( $content, $code ) = MyGet( $url );

  #############################################
  # temporary only !!!
  # todo: avoid using temp file
  #############################################
  my $filename = "/tmp/ftv.xls";
  open (FILE,">$filename");
  print FILE $content;
  close (FILE);

  return( $content, $code );
}

1;
