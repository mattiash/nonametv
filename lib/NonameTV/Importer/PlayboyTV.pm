package NonameTV::Importer::PlayboyTV;

use strict;
use warnings;

=pod

Import data from PlayboyTV's website.

Features:

=cut

use utf8;

use DateTime;
use XML::LibXML;

use NonameTV qw/MyGet Html2Xml FindParagraphs norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/info progress error logdie 
                     log_to_string log_to_string_result/;

use NonameTV::Importer::BaseWeekly;

use base 'NonameTV::Importer::BaseDaily';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  $self->{grabber_name} = "PlayboyTV";

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "America/New_York" );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $month, $day ) = ( $objectname =~ /_(\d+)-(\d+)-(\d+)$/ );

  my $url = sprintf( "%s/%d/%d/%d", $self->{UrlRoot}, $year, $month, $day );

  progress("PlayboyTV: $chd->{xmltvid}: Fetching from $url");

  return( $url, undef );
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  my $doc = Html2Xml( $$cref );
  
  if( not defined $doc ) {
    return (undef, "Html2Xml failed" );
  } 

  my $paragraphs = FindParagraphs( $doc, "//table[\@summary=\"\"]//." );

  my $str = join( "\n", @{$paragraphs} );
  
  return( \$str, undef );
}


sub ContentExtension {
  return 'html';
}

sub FilteredExtension {
  return 'txt';
}

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  $self->{batch_id} = $batch_id;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  
  my( $date ) = ($batch_id =~ /_(.*)/);

  my $dsh = $self->{datastorehelper};

  my @paragraphs = split( /\n/, $$cref );

  if( scalar(@paragraphs) == 0 ) {
    error( "$batch_id: No paragraphs found." ) ;
    return 0;
  }

  $dsh->StartDate( $date, "06:00" ); 

  my $ce = undef;

  foreach my $text (@paragraphs) {

    # It should be possible to ignore these strings with a better
    # FilterContent, because they look slightly different in the html.
    next if $text =~/^Time$/i;
    next if $text =~/^Show$/i;
    next if $text =~/^Synopsis$/i;

    if( $text =~ /^\d+:\d\d\s*[AP]M$/ ){

      if( defined( $ce ) ){
        progress("PlayboyTV: $xmltvid: $ce->{start_time} - $ce->{title}");
        $dsh->AddProgramme( $ce );
      }

      $ce = { start_time => ParseTime( $text ) };
    }
    elsif( not defined( $ce ) ) {
      error("batch_id: Expected time, found '$text'" );
      return 0;
    }
    elsif( not defined( $ce->{title} ) ) {
      $ce->{title} = $text;
    }
    elsif( not defined( $ce->{description} ) ) {
      $ce->{description} = $text;
    }
    else {
      error( "$batch_id: Unexpected text: '$text'" );
      return 0;
    }
  }
  
  $dsh->AddProgramme( $ce ) if( defined( $ce ) );

  return 1;
}

sub ParseTime {
  my( $text ) = @_;

  my ( $hour, $minute, $m ) = ($text =~ /^(\d+)\:(\d{2})\s([AP]M)$/);

  if( ($m eq "AM") and ($hour == 12) ) {
    $hour = 0;
  }
  elsif( ($m eq "PM") and ($hour != 12) ) {
    $hour += 12;
  }

  return "$hour:$minute";
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
