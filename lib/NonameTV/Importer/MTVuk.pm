package NonameTV::Importer::MTVuk;

use strict;
use warnings;

=pod

Import data from mtv.uk website.

Channels: MTV ONE, MTV TWO, MTV HITS, MTV DANCE, MTV BASE, TMF, VH1, VH1 Classic

Features:

=cut

use utf8;

use DateTime;
use XML::LibXML;
use Encode qw/decode encode/;

use NonameTV qw/MyGet norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

use constant {
  T_HEAD1 => 11,
  T_HEAD2 => 12,
  T_HEAD3 => 13,
  T_SHOW => 14,
  T_DESC => 15,
  T_STOP => 16,
};

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/London" );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my $today = DateTime->today();

  # the url is in format 'http://www.mtv.co.uk/channel/vh1/schedule/1'
  # where 1 is for today, 7 is for today + 6 days

  my( $year, $month, $day ) = ( $objectname =~ /_(\d+)-(\d+)-(\d+)$/ );
  my $dt = DateTime->new( 
                          year  => $year,
                          month => $month,
                          day   => $day,
                          time_zone   => 'Europe/London',
  );

  if( DateTime->compare( $dt, $today ) lt 0 ){
    progress( "MTVuk: $objectname: Skipping date in the past " . $dt->ymd() );
    return( undef, undef );
  }

  my $day_diff = $dt->subtract_datetime( $today )->delta_days;
  my $url = sprintf( "%s/channel/%s/schedule/%d", $self->{UrlRoot}, $chd->{grabber_info}, $day_diff + 1 );
  progress( "MTVuk: $objectname: Fetching data from $url" );

  return( $url, undef );
}

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  my( $date ) = ($batch_id =~ /_(.*)$/);

  my @lines = split( /\n/, $$cref );
  if( scalar(@lines) == 0 ) {
    error( "$batch_id: No lines found." ) ;
    return 0;
  }

  $dsh->StartDate( $date, "00:00" );

  my $expect = T_HEAD1;
  my( $time, $title, $url );
  my $description;
  my @shows;
  my $show;

  foreach my $text (@lines) {

#print "TEXT >$text<\n";

    # search for the start of the schedules
    if( $expect eq T_HEAD1 and $text =~ /<!-- start: CONTENT -->/ ){
      $expect = T_HEAD2;
      next;
    }

    # skip the part with the links to days
    if( $expect eq T_HEAD2 and $text =~ /<li class=\"day7\">/ ){
      $expect = T_HEAD3;
      next;
    }

    # the next <ul> is the start of the shows
    if( $expect eq T_HEAD3 and $text =~ /<ul>/ ){
      $expect = T_SHOW;
      next;
    }

    # expect the line with show time and title
    if( $expect eq T_SHOW and $text =~ /^<li><strong>\d{2}:\d{2}/ ){

      # if we have the previous show in the memory
      # push it
      if( $show ){

        $show->{description} = $description if $description;
        $show->{url} = $url if $url;

        push( @shows, $show );
        undef $show;
      }

      ( $time, $url, $title ) = ParseShow( $text );

      $show = {
        channel_id => $chd->{id},
        start_time => $time,
        title => norm($title),
      };

      $expect = T_DESC;
      undef $description;
      next;
    }

    if( $expect eq T_DESC ){

      # if there is no more text

      $description = ParseDescription( $text );

      $expect = T_SHOW;
      next;
    }

    # this is the end of the schedules
    if( ( $expect eq T_SHOW or $expect eq T_DESC ) and $text =~ /<\/ul>/ ){

      $show->{description} = $description if $description;
      $show->{url} = $url if $url;

      push( @shows, $show );

      $expect = T_STOP;
    }

  } # next line

  FlushData( $chd, $dsh, @shows );

  return 1;
}

sub FlushData {
  my ( $chd, $dsh , @data ) = @_;

    if( @data ){
      foreach my $element (@data) {
        next if not $element;
        progress("MTVuk: $chd->{xmltvid}: $element->{start_time} - $element->{title}");
        $dsh->AddProgramme( $element );
      }
    }
}

sub ParseShow
{
  my( $text ) = @_;

  # the format of the line with show info is
  # <li><strong>00:00 - <a href='http://www.mtv.co.uk/channel/mtvuk/shows'> Making The Band 4</a> <a class ='micro'  href='http://www.mtv.co.uk/channel/mtvuk/shows'></a></strong><br />
  # or
  # <li><strong>00:00 - Linkin Park Vs. Jay-Z</strong><br />

  my( $time, $url, $title );

  if( $text =~ / - <a href=\'/ ){
    ( $time, $url, $title ) = ( $text =~ /^<li><strong>(\d{2}:\d{2}) - <a href=\'(.*)\'>\s*(.*)<\/a> <a class/ );
  } else {
    ( $time, $title ) = ( $text =~ /^<li><strong>(\d{2}:\d{2}) - (.*)<\/strong><br \/>/ );
  }

  # don't die on wrong encoding
  eval{ $title = decode( "utf-8", $title ); };
  if( $@ ne "" ){
    error( "Failed to decode $@" );
  }

  return( $time, $url, $title );
}

sub ParseDescription
{
  my( $text ) = @_;

  # the format of the line with the description is
  # Potential buyer Illeana Douglas surprises WEA agent Max when she brings a Feng Shui advisor to her appointments.</li>

  my( $description ) = ( $text =~ /^(.*)<\/li>/ );

  return( $description );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
