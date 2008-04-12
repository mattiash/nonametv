package NonameTV::Importer::NovaTV;

use strict;
use warnings;

=pod

Import data from Word-files delivered via e-mail.  Each day
is handled as a separate batch.

Features:

=cut

use utf8;

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

  $self->{grabber_name} = "NovaTV";

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile
{
  my $self = shift;
  my( $file, $chd ) = @_;

  if( $file !~ /program/i  and $file !~ /\.doc/ ) {
    progress( "NovaTV: Skipping unknown file $file" );
    return;
  }

  progress( "NovaTV: Processing $file" );
  
  $self->{fileerror} = 0;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  
  my $doc;
  $doc = Wordfile2Xml( $file );

  if( not defined( $doc ) ) {
    error( "NovaTV $file: Failed to parse" );
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
    error( "NovaTV $file: No divs found." ) ;
    return;
  }

  my $currdate = undef;
  my $nowyear = DateTime->today->year();
  my $date;

  foreach my $div ($ns->get_nodelist) {
    my( $text ) = norm( $div->findvalue( '.' ) );
#progress("TEXT: $text") if $text;

    if( $text eq "" ) {
      # blank line
    }
    elsif( $text =~ /^PROGRAM NOVE TV za/i ) {
      progress("NovaTV: OK, this is the file with the schedules: $file");
    }
    elsif( $text =~ /^(\S+) (\d+)\.(\d+)/ ) {
      $date = ParseDate( $text , $nowyear );

      if( defined $date ) {
        progress("NovaTV: Date $date");

        $dsh->EndBatch( 1 )
          if defined $currdate;

        my $batch_id = "${xmltvid}_" . $date->ymd();
        $dsh->StartBatch( $batch_id, $channel_id );
        $dsh->StartDate( $date->ymd("-") , "06:00" ); 
        $currdate = $date;
      }

    }
    elsif( $text =~ /^(\d+)\.(\d+) (\S+)/ ) {

      my( $starttime, $title, $genre ) = ParseShow( $text , $date );

      progress("NovaTV: $starttime : $title");

      my $ce = {
        channel_id   => $chd->{id},
	start_time => $starttime->hms(":"),
	title => $title,
      };

      if( $genre ){
        my($program_type, $category ) = $ds->LookupCat( 'NovaTV', $genre );
        AddCategory( $ce, $program_type, $category );
      }

      $dsh->AddProgramme( $ce );

    }
    else {
      #error( "Ignoring $text" );
    }
  }

  $dsh->EndBatch( 1 );
    
  return;
}

sub ParseDate {
  my( $text, $year ) = @_;

  my( $dayname, $day, $month ) = ($text =~ /(\S+) (\d+)\.(\d+)/);
  
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
  my( $title, $genre );

  my( $hour, $min, $string ) = ($text =~ /(\d+)\.(\d+) (.*)/);

  if( $string =~ /,/ ){
    ( $title, $genre ) = $string =~ m/(.*, )(.*)$/;
    if( $title ){
      $title =~ s/, $//;
    }
  }
  else
  {
    $title = $string;
  }

  my $sdt = $date->clone()->add( hours => $hour , minutes => $min );

  return( $sdt , $title , $genre );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
