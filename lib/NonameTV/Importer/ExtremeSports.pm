package NonameTV::Importer::ExtremeSports;

use strict;
use warnings;

=pod

Importer for data from ExtremeSports. 
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

    $self->{grabber_name} = "ExtremeSports";

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    return $self;
}

sub ImportContent
{
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;
  my( $schedule_date , $start_time , $duration );
  my( $event_title , $event_episode_title , $event_short_description );
  my( $genre , $sub_genre , $production_year );
  my( $episode_number , $episode_season , $episode );

  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse('/tmp/extremesports.xls');

  my($iR, $oWkS, $oWkC);

  # There is only one Worksheet in the xls file
  # The name of this sheet is in the format: Extreme_ENG_20060901-20060930
  # We are now not checking against this name

  # The columns in the xls file are:
  # --------------------------------
  # schedule_date start_time duration event_title event_episode_title event_long_description genre sub_genre
  # actor_1 actor_2 actor_3 actor_4 actor_5 actor_6
  # actor_role_1 actor_role_2 actor_role_3 actor_role_4 actor_role_5 actor_role_6
  # directors presenters guests production distribution year_of_production country_of_production
  # episode_number vps teletext teletex_lang live stereo two_tone two_tone_lang subtitle subtitle_lang
  # encription original_language attached_programmes first_showing last_showing repeated_from channel_rating
  # ori_title ori_episode_title version aka_title emissin_duration ori_language black_white colorised
  # certification pilot regional silent dolby 16_9

  foreach my $oWkS (@{$oBook->{Worksheet}}) {
    #print "--------- SHEET:", $oWkS->{Name}, "\n";

    # start from row 1
    #for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
    for(my $iR = 1 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # schedule_date (column 0)
      $oWkC = $oWkS->{Cells}[$iR][0];
      $schedule_date = $oWkC->Value;

      # start_time (column 1)
      $oWkC = $oWkS->{Cells}[$iR][1];
      $start_time = $oWkC->Value;

      # duration (column 2)
      $oWkC = $oWkS->{Cells}[$iR][2];
      $duration = $oWkC->Value;

      # event_title (column 3)
      $oWkC = $oWkS->{Cells}[$iR][3];
      $event_title = $oWkC->Value;

      # event_episode_title (column 4)
      $oWkC = $oWkS->{Cells}[$iR][4];
      if( $oWkC ){
        $event_episode_title = $oWkC->Value;
      }

      # event_short_description (column 5)
      $oWkC = $oWkS->{Cells}[$iR][5];
      $event_short_description = $oWkC->Value;

      # genre (column 8)
      $oWkC = $oWkS->{Cells}[$iR][8];
      $genre = $oWkC->Value;

      # sub_genre (column 9)
      $oWkC = $oWkS->{Cells}[$iR][9];
      $sub_genre = $oWkC->Value;

      # production_year (column 27)
      $oWkC = $oWkS->{Cells}[$iR][27];
      if( $oWkC ){
        $production_year = $oWkC->Value;
      }

      # episode_number (column 29)
      $oWkC = $oWkS->{Cells}[$iR][29];
      $episode_number = $oWkC->Value;
      $episode_season = 0;
      $episode = undef;
      if( $episode_number ){
        if( ($episode_number > 0) and ($episode_season > 0) )
        {
          $episode = sprintf( "%d . %d .", $episode_season-1, $episode_number-1 );
        }
        elsif( $episode_number > 0 )
        {
          $episode = sprintf( ". %d .", $episode_number-1 );
        }
      }

      # format start and end times
      my( $start , $end ) = create_dt( $schedule_date , $start_time , $duration );

      next if ( ! $start_time );

      progress("ExtremeSports: $chd->{xmltvid}: $start - $event_title");

      my $ce = {
        channel_id   => $chd->{id},
        title        => norm($event_title),
        subtitle     => norm($event_episode_title),
        description  => norm($event_short_description),
        start_time   => $start->ymd("-") . " " . $start->hms(":"),
        end_time     => $end->ymd("-") . " " . $end->hms(":"),
      };

      if( defined( $episode ) and ($episode =~ /\S/) )
      {
        $ce->{episode} = norm($episode);
        $ce->{program_type} = 'series';
      }

      my($program_type, $category ) = $ds->LookupCat( "ExtremeSports", $genre );

      AddCategory( $ce, $program_type, $category );

      if( defined( $production_year ) and ($production_year =~ /(\d\d\d\d)/) )
      {
        $ce->{production_date} = "$1-01-01";
      }

      $ds->AddProgramme( $ce );

    } # next row
  } # next worksheet

  unlink("/tmp/extremesports.xls");

  # Success
  return 1;
}

sub create_dt
{
  my( $sd , $st , $du ) = @_;

  # start time
  my ( $month , $day , $year ) = split("-", $sd );

  my ( $hour , $minute ) = split(":", $st );

  if( not defined $year )
  {
    return undef;
  }

  my $sdt = DateTime->new( year   => 2000 + $year,
                           month  => $month,
                           day    => $day,
                           hour   => $hour,
                           minute => $minute,
                           second => 0,
                           time_zone => 'Europe/Zagreb',
                           );
  # times are in CET timezone in original XLS file
  $sdt->set_time_zone( "UTC" );

  # end time
  my ( $hours , $minutes , $seconds ) = split(":", $du );

  my $edt = DateTime->new( year   => 2000 + $year,
                           month  => $month,
                           day    => $day,
                           hour   => $hour,
                           minute => $minute,
                           second => 0,
                           time_zone => 'Europe/Zagreb',
                           );
  # times are in CET timezone in original XLS file
  $edt->set_time_zone( "UTC" );
  $edt->add( hours => $hours,
             minutes => $minutes,
             seconds => $seconds,
             );

  return( $sdt, $edt );
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my @mondays = ( 0 , 31 , 28 , 31 , 30 , 31 , 30 , 31 , 31 , 30 , 31 , 30 , 31 );

  my( $year, $week ) = ($batch_id =~ /_(\d+)-(\d+)/);

  # the url to fetch data from
  # is in the format http://express.extreme.com/Files/Months/Listings/Extreme_ENG_20060901-20060930.xls
  # UrlRoot = http://express.extreme.com/Files/Months/Listings/
  # GrabberInfo = Extreme_ENG (this is the feed name)

  # get current month and check leap year
  my $nowmonth = DateTime->today->month();
  my $is_leap  = DateTime->today->is_leap_year;
  $mondays[2]++ if $is_leap;

  #my $url = $self->{UrlRoot} . $data->{grabber_info} . "_" .
  #          strftime( '%Y%m', localtime ) . "01-" . strftime( '%Y%m', localtime ) . $mondays[$nowmonth] .
  #          ".xls";

  #my $url = "http://express.extreme.com/Files/Months/Listings/Pan%20Euro%20Listings%20Oct%20English%20v7.xls";
  #my $url = "http://express.extreme.com/Files/Months/Listings/Pan%20Euro%20Listings%20Oct%20English%20v7.xls";
  #my $url = "http://express.extreme.com/Files/Months/Listings/Pan%20Euro%20Dec%20Listings%20English.xls";
  #my $url = "http://newsroom.zonemedia.net/Scripts/FileDownload.asp?fName=Extreme%5FPE%5Flistings%5FENG%5FFeb%2Exls&fPath=D%3A%5CZONE%5FPRESS%5CFiles%5CSchedules%5CExtreme%5FPE%5Flistings%5FENG%5FFeb%2Exls";
  #my $url = "http://newsroom.zonemedia.net/Scripts/FileDownload.asp?fName=Extreme+PE+Listing+March+V4%2Exls&fPath=D%3A%5CZONE%5FPRESS%5CFiles%5CSchedules%5CExtreme+PE+Listing+March+V4%2Exls";
  #my $url = "http://newsroom.zonemedia.net/Scripts/FileDownload.asp?fName=Extreme+PE+Listing+April+V4%2Exls&fPath=D%3A%5CZONE%5FPRESS%5CFiles%5CSchedules%5CExtreme+PE+Listing+April+V4%2Exls";
  #my $url = "http://newsroom.zonemedia.net/Scripts/FileDownload.asp?fName=Extreme+PE+May+v2%2Exls&fPath=D%3A%5CZONE%5FPRESS%5CFiles%5CSchedules%5CExtreme+PE+May+v2%2Exls";
  my $url = "http://newsroom.zonemedia.net/Scripts/FileDownload.asp?fName=Extreme+PE+Listings+June+2008+v2%2Exls&fPath=D%3A%5CZONE%5FPRESS%5CFiles%5CSchedules%5CExtreme+PE+Listings+June+2008+v2%2Exls";

  progress("ExtremeSports: Fetching xls file from $url");

  my( $content, $code ) = MyGet( $url );

  #############################################
  # temporary only !!!
  # todo: avoid using temp file
  #############################################
  my $filename = "/tmp/extremesports.xls";
  open (FILE,">$filename");
  print FILE $content;
  close (FILE);

  return( $content, $code );
}

1;
