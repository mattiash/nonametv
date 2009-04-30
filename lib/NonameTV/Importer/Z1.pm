package NonameTV::Importer::Z1;

use strict;
use warnings;

=pod

Channels: Gradska TV Zadar

Import data from Word-files delivered via e-mail.  Each day
is handled as a separate batch.

Features:

=cut

use utf8;

use POSIX;
use DateTime;

use NonameTV qw/MyGet Wordfile2Xml norm AddCategory MonthNumber/;
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

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

#return if ( $file !~ /20090407104828-noname/ );

  if( $file =~ /\.doc$/i ){
    $self->ImportDOC( $file, $channel_id, $xmltvid );
  } elsif( $file =~ /noname$/i ){
    $self->ImportTXT( $file, $channel_id, $xmltvid );
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

  progress( "Z1 DOC: $xmltvid: Processing $file" );
  
  my $doc;
  $doc = Wordfile2Xml( $file );

  if( not defined( $doc ) ) {
    error( "Z1 DOC $xmltvid: $file: Failed to parse" );
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
    error( "Z1 DOC $xmltvid: $file: No divs found." ) ;
    return;
  }

  my $currdate = "x";
  my $date = undef;
  my @ces;
  my $description;

  foreach my $div ($ns->get_nodelist) {

    my( $text ) = norm( $div->findvalue( '.' ) );

    if( isDate( $text ) ) { # the line with the date in format 'Friday 1st August 2008'

      $date = ParseDate( $text );

      if( $date ) {

        progress("Z1 DOC: $xmltvid: Date is $date");

        if( $date ne $currdate ) {

          if( $currdate ne "x" ){
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

      my( $time, $title, $genre, $ep_no, $ep_se ) = ParseShow( $text );

      progress("Z1 DOC: $xmltvid: $time - $title");

      my $ce = {
        channel_id => $channel_id,
        start_time => $time,
        title => norm($title),
      };

      if( $genre ){
        my($program_type, $category ) = $ds->LookupCat( 'Z1', $genre );
        AddCategory( $ce, $program_type, $category );
      }

      if( $ep_no and $ep_se ){
        $ce->{episode} = sprintf( "%d . %d .", $ep_se-1, $ep_no-1 );
      } elsif( $ep_no ){
        $ce->{episode} = sprintf( ". %d .", $ep_no-1 );
      }

      $dsh->AddProgramme( $ce );

    } else {
        # skip
    }
  }

  $dsh->EndBatch( 1 );
    
  return;
}


sub ImportTXT
{
  my $self = shift;
  my( $file, $channel_id, $xmltvid ) = @_;
  
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  progress( "Z1 TXT: $xmltvid: Processing $file" );

  open(HTMLFILE, $file);
  my @lines = <HTMLFILE>;
  close(HTMLFILE);

  my $date;
  my $currdate = "x";

  foreach my $text (@lines){

    $text = norm( $text );
#print ">$text<\n";

    if( isDate( $text ) ){

      $date = ParseDate( $text );

      if( $date ne $currdate ) {
        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;

        progress("Z1 TXT: $xmltvid: Date is: $date");
      }
    } elsif( $date and isShow( $text ) ) {

      my( $time, $title, $genre, $ep_no, $ep_se ) = ParseShow( $text );

      progress("Z1 TXT: $xmltvid: $time - $title");

      my $ce = {
        channel_id => $channel_id,
        start_time => $time,
        title => norm($title),
      };

      if( $genre ){
        my($program_type, $category ) = $ds->LookupCat( 'Z1', $genre );
        AddCategory( $ce, $program_type, $category );
      }

      if( $ep_no and $ep_se ){
        $ce->{episode} = sprintf( "%d . %d .", $ep_se-1, $ep_no-1 );
      } elsif( $ep_no ){
        $ce->{episode} = sprintf( ". %d .", $ep_no-1 );
      }

      $dsh->AddProgramme( $ce );

    } else {
        # skip
    }
  }

  $dsh->EndBatch( 1 );

  return;
}
  
sub isDate {
  my ( $text ) = @_;

  # format 'ÈTVRTAK  23.10.2008.'
  if( $text =~ /^(ponedjeljak|utorak|srijeda|ČETVRTAK|petak|subota|nedjelja)\s+\d+\.\s*\d+\.\s*\d+\.*$/i ){
    return 1;
  }

  # format 'SRIJEDU 21.1.2009.'
  if( $text =~ /^(ponedjeljak|utorak|srijedu|ÈETVRTAK|petak|subotu|nedjelju)\s+\d+\.\s*\d+\.\s*\d+\.*$/i ){
    return 1;
  }

  return 0;
}

sub ParseDate {
  my( $text ) = @_;

  my( $dayname, $day, $month, $year );

  # format 'ÈTVRTAK  23.10.2008.'
  if( $text =~ /^(ponedjeljak|utorak|srijeda|ČETVRTAK|petak|subota|nedjelja)\s+\d+\.\s*\d+\.\s*\d+\.*$/i ){
    ( $dayname, $day, $month, $year ) = ( $text =~ /^(\S+)\s+(\d+)\.\s*(\d+)\.\s*(\d+)\.*$/ );
  }

  # format 'SRIJEDU 21.1.2009.'
  if( $text =~ /^(ponedjeljak|utorak|srijedu|ÈETVRTAK|petak|subotu|nedjelju)\s+\d+\.\s*\d+\.\s*\d+\.*$/i ){
    ( $dayname, $day, $month, $year ) = ( $text =~ /^(\S+)\s+(\d+)\.\s*(\d+)\.\s*(\d+)\.*$/i );
  }

  $year += 2000 if $year lt 100;

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub isShow {
  my ( $text ) = @_;

  # format '15.30 Zap skola,  crtana serija  ( 3/52)'
  if( $text =~ /^\d+\.\d+\s+\S+/i ){
    return 1;
  }

  return 0;
}

sub ParseShow {
  my( $text ) = @_;

  my( $hour, $min, $title, $genre, $ep_no, $ep_se );

  if( $text =~ /\(\d+\/\d+\)/ ){
    ( $ep_no, $ep_se ) = ( $text =~ /\((\d+)\/(\d+)\)/ );
    $text =~ s/\(\d+\/\d+\).*//;
  }

  if( $text =~ /\,.*/ ){
    ( $genre ) = ( $text =~ /\,\s*(.*)$/ );
    $text =~ s/\,.*//;
  }

  ( $hour, $min, $title ) = ( $text =~ /^(\d+)\.(\d+)\s+(.*)$/ );

  return( $hour . ":" . $min , $title , $genre , $ep_no, $ep_se );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
