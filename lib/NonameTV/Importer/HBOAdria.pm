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
use XML::LibXML;

use NonameTV qw/MyGet norm AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;
use NonameTV::Config qw/ReadConfig/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  $self->{grabber_name} = "HBOAdria";

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

  if( $file =~ /\.xml$/i ){
    $self->ImportXML( $file, $channel_id, $channel_xmltvid );
  } elsif( $file =~ /\.html$/i ){
    #$self->ImportHTML( $file, $channel_id, $channel_xmltvid );
  }

  return;
}

sub ImportHTML
{
  my $self = shift;
  my( $file, $channel_id, $channel_xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my $nowday;
  my $starttime;
  my $laststart;
  my $duration;
  my $title;
  my $stereo;
  my $director;
  my $actors;
  my $genre;
  my $rating;

  my $nowyear = DateTime->today->year();
  my $nowmonth = DateTime->today->month();

  progress("HBOAdria: processing HTML/XLS file $file");

  my $te = HTML::TableExtract->new(
    #headers => [qw(TID TITTEL)],
    keep_html => 1
    );

  #$te->parse($$cref);
  $te->parse_file($file);

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
      progress("HBOAdria: Content of the file is '$content'");
      next;
    }

    if ( scalar( $content ) ) {
      $nowday = $content;
      progress("HBOAdria: Date is $nowday");
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
    # column 2: stereo
    #
    $col = norm(@$row[2]);
    $content = HTML::FormatText->new->format(parse_html($col));

    # trim
    $content =~ s/^\s+|\s+$//g;

    if ( $content ) {
      $stereo = $content;

      $stereo = 'mono' if( $stereo =~ /MONO/ );
      $stereo = 'stereo' if( $stereo =~ /STEREO/ );
      $stereo = 'dolby digital' if( $stereo =~ /DOLBY_5\.1/ );
      $stereo = 'dolby' if( $stereo =~ /DOLBY/ );
      $stereo = 'surround' if( $stereo =~ /SURROUND/ );

      #progress("HBOAdria: stereo is $stereo");
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
    if( $start_dt < $laststart ){
      $start_dt->add( days => 1 );
      $end_dt->add( days => 1 );
    }
    $laststart = $start_dt;

    if( defined $nowday ){

      progress("HBOAdria: $channel_xmltvid: $start_dt - $title ($stereo,$rating)");

      my $ce = {
               channel_id   => $channel_id,
               title        => $title,
               start_time   => $start_dt->ymd("-") . " " . $start_dt->hms(":"),
               end_time     => $end_dt->ymd("-") . " " . $end_dt->hms(":"),
               stereo       => $stereo,
               rating       => $rating,
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

sub ImportXML
{
  my $self = shift;
  my( $file, $channel_id, $channel_xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  progress( "HBOAdria: $channel_xmltvid: Processing XML $file" );

  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_file($file); };

  if( not defined( $doc ) ) {
    error( "HBOAdria: $channel_xmltvid: Failed to parse xml file $file" );
    return;
  }

  # find 'ScheduleData' blocks
  my $sdbs = $doc->findnodes( "//ScheduleData" );
  if( $sdbs->size() == 0 ) {
    error( "HBOAdria: $channel_xmltvid: No schedules found" ) ;
    return;
  }

  # browse through ScheduleData nodes
  foreach my $sdb ($sdbs->get_nodelist)
  {

    my @ces;

    my $vwsts = $sdb->findnodes( ".//vwScheduledTitle" );
    foreach my $vwst ($vwsts->get_nodelist)
    {
      my $scheduleid  = $vwst->findvalue( './/ScheduleId' );
      my $starttime = $vwst->findvalue( './/StartTime' );
      my $originaltitle = $vwst->findvalue( './/OriginalTitle' );
      my $episodenumber = $vwst->findvalue( './/EpisodeNumber' );
      my $productiondate = $vwst->findvalue( './/ProductionDate' );
      my $localtitle = $vwst->findvalue( './/LocalTitle' );
      my $localdirector = $vwst->findvalue( './/LocalDirector' );
      my $localcast = $vwst->findvalue( './/LocalCast' );
      my $localgenre1 = $vwst->findvalue( './/LocalGenre1' );
      my $localgenre2 = $vwst->findvalue( './/LocalGenre2' );
      my $locallogline = $vwst->findvalue( './/LocalLogLine' );
      my $localsynopsis = $vwst->findvalue( './/LocalSynopsis' );
      my $schedulingcategory = $vwst->findvalue( './/SchedulingCategory' );
      my $localrating = $vwst->findvalue( './/LocalRating' );

      my $time = ParseStartTime( $starttime );

      next if( ! $time );
      next if( ! $localtitle );

      my $ce = {
               channel_id   => $channel_id,
               title        => $localtitle,
               start_time   => $time,
      };

      $ce->{subtitle} = $originaltitle if $originaltitle;
      $ce->{description} = $localsynopsis if $localsynopsis;
      $ce->{directors} = $localdirector if $localdirector;
      $ce->{actors} = $localcast if $localcast;

      if( $localgenre1 ){
        my($program_type, $category ) = $ds->LookupCat( "HBOAdria", $localgenre1 );
        AddCategory( $ce, $program_type, $category );
      }

      if( $localgenre2 ){
        my($program_type, $category ) = $ds->LookupCat( "HBOAdria", $localgenre2 );
        AddCategory( $ce, $program_type, $category );
      }

      push( @ces , $ce );
    }

    FlushData( $dsh, $channel_id, $channel_xmltvid, @ces );
  }
}

sub bytime {
  $$a{start_time} <=> $$b{start_time};
}

sub FlushData {
  my ( $dsh, $channel_id, $xmltvid, @data ) = @_;

  my $currdate = "x";

  if( @data ){

    # sort data by the start_time field
    my @sorteddata = sort bytime @data;

    foreach my $ce (@sorteddata) {

      my $date = $ce->{start_time}->ymd("-");
      my $time = $ce->{start_time}->hms(":");
      $time =~ s/:\d{2}$//; # strip seconds
      $ce->{start_time} = $time;

      if( $date ne $currdate ) {

        if( $currdate ne "x" ){
          # save last day if we have it in memory
          $dsh->EndBatch( 1 );
        }

        my $batch_id = "${xmltvid}_" . $date;
        $dsh->StartBatch( $batch_id, $channel_id );
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;

        progress("HBOAdria: $xmltvid: Date is $date");
      }

      progress("HBOAdria: $xmltvid: $ce->{start_time} - $ce->{subtitle}");

      $dsh->AddProgramme( $ce );
    }
    $dsh->EndBatch( 1 );
  }
}

sub ParseStartTime
{
  my( $starttime ) = @_;

  if( $starttime !~ /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}\+\d{2}:\d{2}$/ ){
    return undef;
  }

  my( $year, $month, $day, $hour, $min, $sec ) = ( $starttime =~ /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/ );

  my $sdt = DateTime->new( year   => $year,
                           month  => $month,
                           day    => $day,
                           hour   => $hour,
                           minute => $min,
                           second => $sec,
                           time_zone => 'Europe/Zagreb',
                           );

  return $sdt;
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

sub UpdateFiles {
  my( $self ) = @_;

return;
  # get current moment
  my $now = DateTime->today->ymd();

  # the url to fetch data from
  # is in the format http://www.hbo.hr/Download.aspx?Type=ME&ChanelId=HBO&DayFor=2007-10-06
  # UrlRoot = http://www.hbo.hr/Download.aspx
  # GrabberInfo = Type=ME&ChanelId=HBO

  foreach my $data ( @{$self->ListChannels()} ) {
    my $dir = $data->{grabber_info};
    my $xmltvid = $data->{xmltvid};

    my $url = $self->{UrlRoot} . "?Type=ME&" . $data->{grabber_info} . "&DayFor=" . $now;
    progress("HBOAdria: Fetching xls file from $url");

    my( $content, $code ) = MyGet( $url );

    my $filename = $now;
    my $filepath = $self->{FileStore} . '/' . $xmltvid . '/' . $filename . '.html';
    open (FILE,">$filepath");
    print FILE $content;
    close (FILE);

    progress("HBOAdria: Content saved to $filepath");
  }
}

1;
