package NonameTV::Importer::BebeTV;

use strict;
use warnings;

=pod

Import data from Word-files delivered via e-mail.  Each day
is handled as a separate batch.

Features:

=cut

use utf8;

use POSIX;
use DateTime;
use XML::LibXML;
#use Text::Capitalize qw/capitalize_title/;

use NonameTV qw/MyGet Wordfile2Xml Htmlfile2Xml norm AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);


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

  if( ( $file !~ /EN_bebe/i ) and $file !~ /\.doc/ ) {
    progress( "BebeTV: $xmltvid: Skipping unknown file $file" );
    return;
  }

  progress( "BebeTV: $xmltvid: Processing $file" );
  
  my $doc;
  $doc = Wordfile2Xml( $file );

  if( not defined( $doc ) ) {
    error( "BebeTV $file: Failed to parse" );
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
    error( "BebeTV $file: No divs found." ) ;
    return;
  }

  my $currdate = undef;
  my $date = undef;

  foreach my $div ($ns->get_nodelist) {

    my( $text ) = norm( $div->findvalue( '.' ) );

    #print "> $text\n";

    if( $text eq "" ) {
      # blank line
    }
    elsif( isDate( $text ) ) { # the line with date in format '2008.05.26 Monday'

      $date = ParseDate( $text );

      if( defined $date ) {
        progress("BebeTV: $xmltvid: Date is $date");

        if( defined $currdate ){
          $dsh->EndBatch( 1 )
        }

        my $batch_id = "${xmltvid}_" . $date;
        $dsh->StartBatch( $batch_id, $channel_id );
        $dsh->StartDate( $date, "00:00" ); 
        $currdate = $date;
      }
    }
    elsif( isShow( $text ) ) { # the line with show in format '2008.05.26 0:15 Title'

      my( $time, $title, $episinfo, $duration ) = ParseShow( $text );

      progress("BebeTV: $xmltvid: $time - $title");

      my $ce = {
        channel_id   => $chd->{id},
	start_time => $time,
	title => norm($title),
      };

      my $episode = undef;
      my ( $ep_nr , $ep_se );
      if( $episinfo ){

        if( $episinfo =~ /^\d+\/\d+$/ ){
          ( $ep_nr , $ep_se ) = ( $episinfo =~ /(\d+)\/(\d+)/ );
          $episode = sprintf( "%d . %d .", $ep_se-1, $ep_nr-1 );
        }
        elsif( $episinfo =~ /^\d+$/ )
        {
          $ep_nr = ( $episinfo =~ /(\d+)/ );
          $episode = sprintf( ". %d .", $ep_nr-1 );
        }

        $ce->{episode} = norm($episode);
        $ce->{program_type} = 'series';

      }

      $dsh->AddProgramme( $ce );

    }
  }

  $dsh->EndBatch( 1 );
    
  return;
}

sub isDate {
  my( $text ) = @_;

  if( $text =~ /^\d{4}\.\d{2}\.\d{2}\.*\s+\S+$/ ){
    return 1;
  }

  return 0;
}

sub ParseDate {
  my( $text ) = @_;

  my( $year , $month , $day , $dayname ) = ( $text =~ /(\d{4})\.(\d{2})\.(\d{2})\.*\s+(\S+)/ );
  
  $year += 2000 if $year lt 100;

  return sprintf( "%04d-%02d-%02d", $year, $month, $day );
}

sub isShow {
  my( $text ) = @_;

  if( $text =~ /^\d+\.\d+\.\d+\.*\s+\d+:\d+/ ){
    return 1;
  }

  return 0;
}

sub ParseShow {
  my( $text ) = @_;

  my( $hour, $min, $sec, $string );

  if( $text =~ /^\d+\.\d+\.\d+\.*\s+\d+:\d+\s+.*$/ ){
    ( $hour, $min, $string ) = ( $text =~ /^\d+\.\d+\.\d+\.*\s+(\d+):(\d+)\s+(.*)$/ );
  } elsif( $text =~ /^\d+\.\d+\.\d+\.*\s+\d+:\d+:\d+\s+.*$/ ){
    ( $hour, $min, $sec, $string ) = ( $text =~ /^\d+\.\d+\.\d+\.*\s+(\d+):(\d+):(\d+)\s+(.*)$/ );
  }

  my( $title, $episode, $duration );
  if( $string =~ /Ep\.:(\d+)\/(\d+)/ ){ # example: 'Magic fingers	Ep.:2/1	2'
  	( $title, $episode, $duration ) = ( $string =~ /(.*)Ep\.:(\d+\/\d+)\s+(\d+)/ );
  } elsif( $string =~ /Ep\.:\d+\s+\d+/ ){ # example: Waterworld	Ep.:6	15'
  	( $title, $episode, $duration ) = ( $string =~ /(.*)Ep\.:(\d+)\s+(\d+)/ );
  } else {
    $title = $string;
  }

  my $time = sprintf( "%02d:%02d", $hour, $min );

  return( $time , $title , $episode , $duration );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
