package NonameTV::Importer::Tiji;

use strict;
use warnings;

=pod

Import data from CSV-files delivered via e-mail.

Features:

=cut

use utf8;

use DateTime;
use Text::CSV;
use Data::Dumper;
use File::Temp qw/tempfile/;

use NonameTV qw/norm AddCategory/;
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

  $self->{grabber_name} = "Tiji";

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  return if( $file !~ /\.csv$/i );
  progress( "Tiji: $xmltvid: Processing $file" );

  my $date;
  my $time;
  my $title;
  my $episode;
  my $currdate = "x";

  open my $CSVFILE, "<", $file or die $!;

  my $csv = Text::CSV->new( {
    sep_char => ';',
    allow_whitespace => 1,
    blank_is_undef => 1,
    binary => 1,
  } );

  # get the column names from the first line
  my @columns = $csv->column_names( $csv->getline( $CSVFILE ) );

  # main loop
  while( my $row = $csv->getline_hr( $CSVFILE ) ){

    if( $row->{'DATE'} ) {

      $date = ParseDate( $row->{'DATE'} );

      if( $date ne $currdate ){

        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "04:00" );
        $currdate = $date;
      }
    }

    if( $row->{'HEURE'} ) {

      $time = $row->{'HEURE'};
      next if ( $time !~ /^\d\d\:\d\d$/ );
    }

    if( $row->{'TITRE ORIGINAL'} ) {

      $title = $row->{'TITRE ORIGINAL'};
      next if ( ! $title );
    }

#print "03: $row->{'SUR-TITRE'}\n";
#print "04: $row->{'TITRE ORIGINAL'}\n";
#print "05: $row->{'FORMAT'}\n";
#print "06: $row->{'EPISODE'}\n";
#print "07: $row->{'SOUS-TITRE / THEME'}\n";
#print "08: $row->{'PRESENTATEUR'}\n";
#print "09: $row->{'REDIFF'}\n";
#print "10: $row->{'SYNOPSIS/CONCEPT'}\n";

    progress( "Tiji: $xmltvid: $time - $title" );

    my $ce = {
      channel_id => $channel_id,
      title => $title,
      start_time => $time,
    };

    if( $row->{'SOUS-TITRE / THEME'} ) {
      #$ce->{subtitle} = $row->{'SOUS-TITRE / THEME'};
    }

    if( $row->{'FORMAT'} ) {
      my $genre = norm($row->{'FORMAT'});
      my($program_type, $category ) = $ds->LookupCat( "Tiji", $genre );
      AddCategory( $ce, $program_type, $category );
    }

    if( $row->{'EPISODE'} ) {

      my $ep_nr = int( $row->{'EPISODE'} );
      my $ep_se = 0;
      if( ($ep_nr > 0) and ($ep_se > 0) )
      {
        $episode = sprintf( "%d . %d .", $ep_se-1, $ep_nr-1 );
      }
      elsif( $ep_nr > 0 )
      {
        $episode = sprintf( ". %d .", $ep_nr-1 );
      }

      $ce->{episode} = norm($episode);
    }

    if( $row->{'PRESENTATEUR'} ){
      $ce->{presenters} = norm($row->{'PRESENTATEUR'});
    }

    if( $row->{'SYNOPSIS/CONCEPT'} ){
      $ce->{description} = norm($row->{'SYNOPSIS/CONCEPT'});
    }

    $dsh->AddProgramme( $ce );
  }

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate {
  my( $text ) = @_;
  my( $day , $month , $year );

  return undef if( ! $text );

  if( $text =~ /^\d\d\/\d\d\/\d\d\d\d/ ){
    ( $day , $month , $year ) = ( $text =~ /^(\d\d)\/(\d\d)\/(\d\d\d\d)/ );
  } else {
    $day = undef;
  }

  my $date = DateTime->new( year   => $year,
                            month  => $month,
                            day    => $day,
                            hour   => 0,
                            minute => 0,
                            second => 0,
                            nanosecond => 0,
                            time_zone => 'Europe/Paris',
  );

  return $date->ymd("-");
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
