package NonameTV::Importer::ZoneReality;

use strict;
use warnings;

=pod

Channels: ZoneReality

Import data from Word-files delivered via e-mail.  Each day
is handled as a separate batch.

Features:

=cut

use utf8;

use POSIX;
use DateTime;
use XML::LibXML;
#use Text::Capitalize qw/capitalize_title/;

use NonameTV qw/MyGet Wordfile2Xml Htmlfile2Xml norm AddCategory MonthNumber/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  $self->{grabber_name} = "ZoneReality";

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $channel_id = $chd->{id};
  my $xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  if( $file =~ /\.xml$/i ){
    $self->ImportXML( $file, $channel_id, $xmltvid );
  } elsif( $file =~ /\.doc$/i ){
    $self->ImportDOC( $file, $channel_id, $xmltvid );
  }

  return;
}

sub ImportDOC
{
  my $self = shift;
  my( $file, $channel_id, $xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  
  return if( $file !~ /\.doc$/i );

  progress( "ZoneReality: $xmltvid: Processing $file" );
  
  my $doc;
  $doc = Wordfile2Xml( $file );

  if( not defined( $doc ) ) {
    error( "ZoneReality $xmltvid: $file: Failed to parse" );
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
    error( "ZoneReality $xmltvid: $file: No divs found." ) ;
    return;
  }

  my $currdate = "x";
  my $date = undef;
  my @ces;
  my $description;

  foreach my $div ($ns->get_nodelist) {

    my( $text ) = norm( $div->findvalue( '.' ) );

    # skip the bottom of the document
    # all after 'TJEDNI PROGRAM'
    last if( $text =~ /^Produced by EBS New Media/ );

print ">$text<\n";

    if( isDate( $text ) ) { # the line with the date in format 'FRIDAY 1 AUGUST 2008 - ZONE REALITY EMEA 1'
print "DATUM--------------------------------------\n";
      $date = ParseDate( $text );

      if( $date ) {

        progress("ZoneReality: $xmltvid: Date is $date");

        if( $date ne $currdate ) {

          if( $currdate ne "x" ){
            # save last day if we have it in memory
            FlushDayData( $xmltvid, $dsh , @ces );
            $dsh->EndBatch( 1 );
          }

          my $batch_id = "${xmltvid}_" . $date;
          $dsh->StartBatch( $batch_id, $channel_id );
          $dsh->StartDate( $date , "00:00" ); 
          $currdate = $date;
        }
      }

      # empty last day array
      undef @ces;
      undef $description;

    } elsif( isShow( $text ) ) {
print "SHOW--------------------------------------\n";

      my( $time, $title, $genre ) = ParseShow( $text );

      my $ce = {
        channel_id => $channel_id,
        start_time => $time,
        title => norm($title),
      };

      if( $genre ){

        my($program_type, $category ) = $ds->LookupCat( "ZoneReality", $genre );
        AddCategory( $ce, $program_type, $category );

        $ce->{description} = $genre;
      }

      # add the programme to the array
      # as we have to add description later
      push( @ces , $ce );

    } else {
print "OPIS--------------------------------------\n";

        # the last element is the one to which
        # this description belongs to
        my $element = $ces[$#ces];

        # remove ' - ' from the start
  	$text =~ s/^\s*-\s*//;
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

        progress("ZoneReality: $xmltvid: $element->{start_time} - $element->{title}");

        $dsh->AddProgramme( $element );
      }
    }
}

sub isDate {
  my ( $text ) = @_;

  # format 'FRIDAY 1 AUGUST 2008 - ZONE REALITY EMEA 1'
  if( $text =~ /^(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\s+\d+\s+\S+\s+\d+\s+- ZONE REALITY EMEA 1$/i ){
    return 1;
  }

  return 0;
}

sub ParseDate {
  my( $text ) = @_;

  my( $dayname, $day, $monthname, $year ) = ( $text =~ /^(\S+)\s+(\d+)\s+(\S+)\s+(\d+)/ );

  my $month = MonthNumber( $monthname, 'en' );

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub isShow {
  my ( $text ) = @_;

  # format '12:40 Glazbeni program'
  if( $text =~ /^\d+\:\d+\s+.*/i ){
    return 1;
  }

  return 0;
}

sub ParseShow {
  my( $text ) = @_;

  my( $hour, $min, $title, $genre );

#  if( $text =~ /\,/ ){
#    ( $genre ) = ( $text =~ /\,\s*(.*)/ );
#    $text =~ s/\,\s*.*//;
#  }
    
  ( $hour, $min, $title ) = ( $text =~ /^(\d+)\:(\d+)\s+(.*)/ );

  return( $hour . ":" . $min , $title , $genre );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
