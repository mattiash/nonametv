package NonameTV::Importer::Poker;

use strict;
use warnings;

=pod

Import data from Poker Channel Europe website.

Features:

=cut

use utf8;

use DateTime;
use XML::LibXML;
use Encode qw/decode encode/;

use NonameTV qw/MyGet Html2Xml FindParagraphs norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseOne;

use base 'NonameTV::Importer::BaseOne';

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

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  # the url is the one that is specified in UrlRoot and it never changes
  my $url = $self->{UrlRoot};

  my( $content, $code ) = MyGet( $url );

  return( $content, $code );
}

sub ImportContent
{
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;

  my $dsh = $self->{datastorehelper};

  my $doc = Html2Xml( $$cref );
  if( not defined $doc ) {
    return (undef, "Html2Xml failed" );
  }

  my $paragraphs = FindParagraphs( $doc, "//div//p//." );

  my $str = join( "\n", @{$paragraphs} );

  if( scalar(@{$paragraphs}) == 0 ) {
    error( "$batch_id: No paragraphs found." ) ;
    return 0;
  }

  my $date;
  my $currdate = "x";

  foreach my $text (@{$paragraphs}) {

#print ">$text<\n";

    if( isDate( $text ) ){

      $date = ParseDate( $text );
      next if not $date;

      if( $date ne $currdate ) {
        if( $currdate ne "x" ) {
          #$dsh->EndBatch( 1 );
        }

        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;

        progress("Poker: $chd->{xmltvid}: Date is: $date");
      }

    } elsif( isShow( $text ) ){

      my( $time, $title ) = ParseShow( $text );

      progress( "Poker: $chd->{xmltvid}: $time - $title" );

      my $ce = {
        channel_id => $chd->{id},
        title => $title,
        start_time => $time,
      };

      $dsh->AddProgramme( $ce );

    } else {
      #error( "$batch_id: Unexpected text: '$text'" );
    }
  }
  
  return 1;
}

sub isDate
{
  my( $text ) = @_;

  # the date is in format 'Wednesday 19th'
  if( $text =~ /^(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\s+\d+(st|nd|rd|th)$/i ){
    return 1;
  }

  return 0;
}

sub isShow
{
  my( $text ) = @_;

  # the show is in format '1800- Premiere: World Series Gold: WSOP 05: Pot Limit Hold'em ($2K) (11/32)
  if( $text =~ /^\d{4}-\s+.*$/i ){
    return 1;
  }

  return 0;
}

sub ParseDate
{
  my( $text ) = @_;

  # the date is in format 'Wednesday 19th'
  my( $dayname, $day ) = ( $text =~ /^(\S+)\s+(\d+)/ );

  my $year = DateTime->today->year;
  my $month = DateTime->today->month;

  return sprintf( "%04d-%02d-%02d", $year, $month, $day );
}

sub ParseShow
{
  my( $text ) = @_;

  # the show is in format '1800- Premiere: World Series Gold: WSOP 05: Pot Limit Hold'em ($2K) (11/32)
  my( $hour, $min, $title ) = ( $text =~ /^(\d{2})(\d{2})-\s+(.*)$/ );

  return( $hour . ":" . $min, $title );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
