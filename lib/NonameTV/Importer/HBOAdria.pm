package NonameTV::Importer::HBOAdria;

use strict;
use warnings;

=pod

Importer for data from HBO Adria. 
One file per month downloaded from hbo.hr site.
The downloaded file is in html-format.

Features:

=cut

use POSIX qw/strftime/;
use DateTime;
use Unicode::String qw(utf8 latin1);
use Locale::Recode;
use HTML::TableExtract;
use HTML::Parse;
use HTML::FormatText;

use NonameTV qw/MyGet norm AddCategory/;
use NonameTV::Log qw/info progress error logdie/;

use NonameTV::Importer::BaseOne;

use base 'NonameTV::Importer::BaseOne';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{grabber_name} = "HBOAdria";

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    return $self;
}

sub ImportContent
{
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $nowday;
  my $starttime;
  my $laststart;
  my $duration;
  my $title;
  my $director;
  my $actors;
  my $genre;
  my $rating;

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  $ds->{SILENCE_END_START_OVERLAP}=1;

  my $nowyear = DateTime->today->year();
  my $nowmonth = DateTime->today->month();

  progress("HBOAdria: processing data for $nowmonth $nowyear");

  my $te = HTML::TableExtract->new(
    #headers => [qw(TID TITTEL)],
    keep_html => 1
    );

  $te->parse($$cref);

  my $table = $te->first_table_found();

  foreach my $row ($table->rows) {

    #
    # column 0: day of the month
    #
    my $col = norm(@$row[0]);
    my $content = HTML::FormatText->new->format(parse_html($col));

    # trim
    $content =~ s/^\s+|\s+$//g;

    if ( $content =~ /Filmovi/ ) {
      progress($content);
      next;
    }

    if ( scalar( $content ) ) {
      $nowday = $content;
      #progress("HBOAdria: date is now $nowday");
    }

    #
    # column 1: start time
    #
    $col = norm(@$row[1]);
    $content = HTML::FormatText->new->format(parse_html($col));

    # trim
    $content =~ s/^\s+|\s+$//g;

    if ( $content ) {
      $starttime = $content;
      #progress("HBOAdria: start time is $starttime");
    }

    #
    # column 2: audio
    #
    $col = norm(@$row[2]);
    $content = HTML::FormatText->new->format(parse_html($col));

    # trim
    $content =~ s/^\s+|\s+$//g;

    if ( $content ) {
      my $audio = $content;
      #progress("HBOAdria: audio is $audio");
    }

    #
    # column 3: title
    #
    $col = norm(@$row[3]);
    $content = HTML::FormatText->new->format(parse_html($col));

    # trim
    $content =~ s/^\s+|\s+$//g;

    # recode the title from windows-1250 to UTF-8
    my $cod = Locale::Recode->new( from => 'windows-1250' , to => 'UTF-8' );
    $cod->recode( $content );

    if ( $content ) {
      $title = $content;
      #progress("HBOAdria: title is $title");
    }

    #
    # column 4: director
    #
    $col = norm(@$row[4]);
    $content = HTML::FormatText->new->format(parse_html($col));

    # trim
    $content =~ s/^\s+|\s+$//g;

    if ( $content ) {
      $director = $content;
      #progress("HBOAdria: director is $director");
    }

    #
    # column 5: actors
    #
    $col = norm(@$row[5]);
    $content = HTML::FormatText->new->format(parse_html($col));

    # trim
    $content =~ s/^\s+|\s+$//g;

    if ( $content ) {
      $actors = $content;
      #progress("HBOAdria: actors is $actors");
    }

    #
    # column 6: genre
    #
    $col = norm(@$row[6]);
    $content = HTML::FormatText->new->format(parse_html($col));

    # trim
    $content =~ s/^\s+|\s+$//g;

    if ( $content ) {
      $genre = $content;
      #progress("HBOAdria: genre is $genre");
    }

    #
    # column 7: rating
    #
    $col = norm(@$row[7]);
    $content = HTML::FormatText->new->format(parse_html($col));

    # trim
    $content =~ s/^\s+|\s+$//g;

    if ( $content ) {
      $rating = $content;
      #progress("HBOAdria: rating is $rating");
    }

    #
    # column 8: duration
    #
    $col = norm(@$row[8]);
    $content = HTML::FormatText->new->format(parse_html($col));

    # trim
    $content =~ s/^\s+|\s+$//g;

    if ( $content ) {
      $duration = $content;
      #progress("HBOAdria: duration is $duration");
    }

    #
    # set right times
    #
    my( $start_dt , $end_dt ) = create_dt( $nowyear , $nowmonth , $nowday , $starttime , $duration );
#print "LASTS: $laststart\n";
#print "START: $start_dt\n";
#print "END  : $end_dt\n";
    if( $start_dt < $laststart ){
      $start_dt->add( days => 1 );
      $end_dt->add( days => 1 );
    }
    $laststart = $start_dt;

    if( defined $nowday ){

      my $ce = {
               channel_id   => $chd->{id},
               title        => $title,
               start_time   => $start_dt->ymd("-") . " " . $start_dt->hms(":"),
               end_time     => $end_dt->ymd("-") . " " . $end_dt->hms(":"),
               directors    => $director,
               actors       => $actors,
      };

      my($program_type, $category ) = $ds->LookupCat( "HBOAdria", $genre );
      AddCategory( $ce, $program_type, $category );

      $ds->AddProgramme( $ce );
    }

  }

  # Success
  return 1;
}

sub create_dt
{
  my( $ny , $nm , $nd , $st , $du ) = @_;

  if( not defined $nd )
  {
    return undef;
  }

  # start time
  my ( $hour , $minute ) = split( ":" , $st );

  my $sdt = DateTime->new( year   => $ny,
                           month  => $nm,
                           day    => $nd,
                           hour   => $hour,
                           minute => $minute,
                           second => 0,
                           time_zone => 'Europe/Zagreb',
                           );

  # times are in CET timezone in original file
  $sdt->set_time_zone( "UTC" );

  # end time
  $du =~ s/'//gi;
  my $edt = $sdt->clone->add( minutes => $du );

  return( $sdt, $edt );
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my @mondays = ( 0 , 31 , 28 , 31 , 30 , 31 , 30 , 31 , 31 , 30 , 31 , 30 , 31 );

  my( $year, $week ) = ($batch_id =~ /_(\d+)-(\d+)/);

  # the url to fetch data from
  # is in the format http://www.hbo.hr/Download.aspx?Type=ME&ChanelId=HBO&DayFor=2007-10-06
  # UrlRoot = http://www.hbo.hr/Download.aspx
  # GrabberInfo = Type=ME&ChanelId=HBO

  # get current month and check leap year
  my $now = DateTime->today->ymd();

  my $url = $self->{UrlRoot} . "?Type=ME&" . $data->{grabber_info} . "&DayFor=" . $now;

  progress("HBOAdria: Fetching xls file from $url");

  my( $content, $code ) = MyGet( $url );

  #############################################
  # temporary only !!!
  # todo: avoid using temp file
  #############################################
  my $filename = "/tmp/hboadria.xls";
  open (FILE,">$filename");
  print FILE $content;
  close (FILE);

  return( $content, $code );
}

1;
