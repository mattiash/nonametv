package NonameTV::Importer::GlobalListings;

use strict;
use warnings;

=pod

Import data from Word-files delivered via e-mail.  Each day
is handled as a separate batch.

The grabber_info field should be set to 'HH:MM', as this is used
to determine the start of each day batch.

Features:

=cut

use utf8;

use POSIX;
use DateTime;
use XML::LibXML;
#use Text::Capitalize qw/capitalize_title/;

use NonameTV qw/MyGet Wordfile2Xml Htmlfile2Xml norm AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/info progress error logdie 
                     log_to_string log_to_string_result/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  $self->{grabber_name} = "GlobalListings";

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile
{
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  my $firstshowtime = $chd->{grabber_info};
  
  defined( $chd->{grabber_info} ) or die "You must specify the time of the first show in grabber_info";
  if( $chd->{grabber_info} !~ /^\d\d:\d\d$/ ){
    error( "GlobalListings: $xmltvid: Invalid grabber_info - should be set to HH:MM" );
    return;
  }

  progress( "GlobalListings: $xmltvid: Processing $file" );
  
  my $doc;
  $doc = Wordfile2Xml( $file );

  if( not defined( $doc ) ) {
    error( "GlobalListings $xmltvid: $file: Failed to parse" );
    return;
  }

  my @nodes = $doc->findnodes( '//span[@style="text-transform:uppercase"]/text()' );
  foreach my $node (@nodes) {
    my $str = $node->getData();
    $node->setData( uc( $str ) );
  }
  
  # Find all paragraphs.
  my $ns = $doc->find( "//div" );
  
  if( $ns->size() == 0 ) {
    error( "GlobalListings $xmltvid: $file: No divs found." ) ;
    return;
  }

  my $fileok = 0;

  my $currdate = undef;
  my $date = undef;
  my @ces;
  my $description;
  my $subtitle;

  foreach my $div ($ns->get_nodelist) {

    my( $text ) = norm( $div->findvalue( '.' ) );

#print "> $text\n";

    if( $text eq "" ) {
      # blank line
    }
    elsif( $text =~ /www\.globallistings\.info/i ) {
      progress("GlobalListings: $xmltvid: OK, this is the file with the schedules: $file");
      $fileok = 1;
    }

    # we have to find one string in the file
    # that says this is the GlobalListings file
    # and we don't process the rest of the file
    # if this string was not found on the top
    next if( ! $fileok );

    if( isDate( $text ) ) { # the line with the date in format 'Tuesday 1 July 2008'

      $date = ParseDate( $text );

      if( defined $date ) {
        progress("GlobalListings: $xmltvid: Date $date");

        if( defined $currdate ){

          # save last day if we have it in memory
          FlushDayData( $xmltvid, $dsh , @ces );
          $dsh->EndBatch( 1 )

        }

        my $batch_id = "${xmltvid}_" . $date->ymd();
        $dsh->StartBatch( $batch_id, $channel_id );
        $dsh->StartDate( $date->ymd("-") , $firstshowtime ); 
        $currdate = $date;
      }

      # empty last day array
      undef @ces;
      undef $description;
      undef $subtitle;
    }
    elsif( $text =~ /^(\d+)\.(\d+) (\S+)/ ) { # the line with the show in format '19.30 Show title: Episode 4'

      my( $starttime, $title, $episode ) = ParseShow( $text , $date );

      my $ce = {
        channel_id   => $chd->{id},
	start_time => $starttime->hms(":"),
	title => norm($title),
      };

      if( $episode ){
        $ce->{episode} = sprintf( ". %d .", $episode-1 );
      }

      # add the programme to the array
      # as we have to add description later
      push( @ces , $ce );
    }

    else {

        # the last element is the one to which
        # this description belongs to
        my $element = $ces[$#ces];

        $element->{description} .= $text;

    }
  }

  # save last day if we have it in memory
  FlushDayData( $xmltvid, $dsh , @ces );

  $dsh->EndBatch( 1 );
    
  return;
}

sub FlushDayData {
  my ( $xmltvid, $dsh , @data ) = @_;

    if( @data ){
      foreach my $element (@data) {

        progress("GlobalListings: $xmltvid: $element->{start_time} - $element->{title}");

        $dsh->AddProgramme( $element );
      }
    }
}

sub isDate {
  my ( $text ) = @_;

  # try 'Sunday1 June 2008'
  return 1 if( $text =~ /^Saturday(\d+)\s(\S+)\s(\d{4})/i );
  return 1 if( $text =~ /^Sunday(\d+)\s(\S+)\s(\d{4})/i );
  return 1 if( $text =~ /^Monday(\d+)\s(\S+)\s(\d{4})/i );
  return 1 if( $text =~ /^Tuesday(\d+)\s(\S+)\s(\d{4})/i );
  return 1 if( $text =~ /^Wednesday(\d+)\s(\S+)\s(\d{4})/i );
  return 1 if( $text =~ /^Thursday(\d+)\s(\S+)\s(\d{4})/i );
  return 1 if( $text =~ /^Friday(\d+)\s(\S+)\s(\d{4})/i );

  return 1 if( $text =~ /^subota(\d+)\.\s(\S+)\s(\d{4})\./i );
  return 1 if( $text =~ /^nedjelja(\d+)\.\s(\S+)\s(\d{4})\./i );
  return 1 if( $text =~ /^ponedjeljak(\d+)\.\s(\S+)\s(\d{4})\./i );
  return 1 if( $text =~ /^utorak(\d+)\.\s(\S+)\s(\d{4})\./i );
  return 1 if( $text =~ /^srijeda(\d+)\.\s(\S+)\s(\d{4})\./i );
  return 1 if( $text =~ /^[[:lower:]]etvrtak(\d+)\.\s(\S+)\s(\d{4})\./i );
  return 1 if( $text =~ /^petak(\d+)\.\s(\S+)\s(\d{4})\./i );

  return 0;
}

sub ParseDate {
  my( $text ) = @_;

#print "TEXT: $text\n";
  # try the 1st English format 'Sunday1 June 2008'
  my( $day, $monthname, $year ) = ($text =~ /(\d+)\s(\S+)\s(\d+)/);

  if( not defined $monthname ){
    ( $day, $monthname, $year ) = ($text =~ /(\d+)\.\s(\S+)\s(\d+)\./);
  }
#print "day: $day\n";
#print "mon: $monthname\n";
#print "yea: $year\n";


  my $month;
  $month = 1 if( $monthname =~ /January/i );
  $month = 2 if( $monthname =~ /February/i );
  $month = 3 if( $monthname =~ /March/i );
  $month = 4 if( $monthname =~ /April/i );
  $month = 5 if( $monthname =~ /May/i );
  $month = 6 if( $monthname =~ /June/i );
  $month = 7 if( $monthname =~ /July/i );
  $month = 8 if( $monthname =~ /August/i );
  $month = 9 if( $monthname =~ /September/i );
  $month = 10 if( $monthname =~ /October/i );
  $month = 11 if( $monthname =~ /November/i );
  $month = 12 if( $monthname =~ /December/i );
  
  $month = 5 if( $monthname =~ /svibnja/i );
  $month = 6 if( $monthname =~ /lipnja/i );
  $month = 7 if( $monthname =~ /srpnja/i );

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => 0,
                          minute => 0,
                          second => 0,
                          time_zone => 'Europe/Zagreb',
  );

  return $dt;
}

sub ParseShow {
  my( $text, $date ) = @_;
  my( $title, $episode );

  my( $hour, $min, $string ) = ($text =~ /(\d+)\.(\d+)\s(.*)/);

  $string =~ s/NA HRVATSKOM //;

  if( $string =~ /: Episode/ ){
    ( $title, $episode ) = $string =~ m/(\S+):\s+Episode\s+(\d+)/;
  }
#  elsif( $string =~ /: Epizoda/ ){
#    ( $title, $episode ) = $string =~ m/(\S+):\s+Epizoda\s+(\d+)/;
#  }
  else
  {
    $title = $string;
  }

  my $sdt = $date->clone()->add( hours => $hour , minutes => $min );

  return( $sdt , $title , $episode );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
