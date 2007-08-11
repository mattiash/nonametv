package NonameTV::Importer::NASN;

use strict;
use warnings;

=pod

Import data from NASN's website.

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

  $self->{grabber_name} = "NASN";

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/London" );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $month, $day ) = ( $objectname =~ /_(\d+)-(\d+)-(\d+)$/ );
  my $dt = DateTime->new( 
                          year  => $year,
                          month => $month,
                          day   => $day 
                          );

  my $today = DateTime->today( time_zone=>'local' );
  my $day_diff = $dt->subtract_datetime( $today )->delta_days;

  my $url = sprintf( "%s/%2d", $self->{UrlRoot}, $day_diff );
  
  return( $url, undef );
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  my $doc = Html2Xml( $$cref );
  
  if( not defined $doc ) {
    return (undef, "Html2Xml failed" );
  } 

  my $paragraphs = FindParagraphs( $doc, 
      "//div[\@class='div_contentfull']//table//table//table//." );

  my $str = join( "\n", @{$paragraphs} );
  
  return( \$str, undef );
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
    next if $text =~/^All times in BST/i;

    if( $text =~ /^\d+.\d\d\s*[ap]m$/ ) {
      $dsh->AddProgramme( $ce ) if( defined( $ce ) );

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

  my( $hour, $minute, $m ) = ($text =~ /^(\d+)\.(\d{2})([ap]m)$/);

  if( ($m eq "am") and ($hour == 12) ) {
    $hour = 0;
  }
  elsif( ($m eq "pm") and ($hour != 12) ) {
    $hour += 12;
  }

  return "$hour:$minute";
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
