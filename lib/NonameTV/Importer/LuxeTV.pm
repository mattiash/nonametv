package NonameTV::Importer::LuxeTV;

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

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  return if( $file !~ /\.csv$/i );
  if( $file =~ /FR\.csv$/i ){
    progress( "LuxeTV: $xmltvid: Skipping $file" );
    return;
  }

  progress( "LuxeTV: $xmltvid: Processing $file" );

  my $date;
  my $time;
  my $duration;
  my $title;
  my $episode;
  my $currdate = "x";

  open my $CSVFILE, "<", $file or die $!;

  my $csv = Text::CSV->new( {
    sep_char => "\t",
    allow_whitespace => 0,
    blank_is_undef => 1,
    binary => 1,
    verbatim => 1,
  } );

  # get the column names from the first line
  my @columns = $csv->column_names( $csv->getline( $CSVFILE ) );
#foreach my $c (@columns) {
#print "$c\n";
#}

  # main loop
  while( my $row = $csv->getline_hr( $CSVFILE ) ){

    if( $row->{'Date'} ) {

print "DATE1: $row->{'Date'}\n";
      $date = ParseDate( $row->{'Date'} );
print "DATE2: $date\n";
next;
      next if( ! $date );

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

    if( $row->{'Time'} ) {
      $time = ParseTime( $row->{'Time'} );
      next if( ! $time );
print "TIME: $time\n";
    }

    if( $row->{'Duration'} ) {
      $duration = $row->{'Duration'};
      next if ( $duration !~ /^\d\d\:\d\d\:\d\d\.\d\d$/ );
    }

    if( $row->{'Title'} ) {
      $title = $row->{'Title'};
      next if ( ! $title );
    }

    progress( "LuxeTV: $xmltvid: $time - $title" );

    my $ce = {
      channel_id => $channel_id,
      title => $title,
      start_time => $time,
    };

    if( $row->{'Episode'} ) {

      my $ep_nr = int( $row->{'Episode'} );
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

    if( $row->{'Synopsis'} ){
      $ce->{description} = norm($row->{'Synopsis'});
    }

    if( $row->{'Genre'} ) {
      my $genre = norm($row->{'Genre'});
      my($program_type, $category ) = $ds->LookupCat( "LuxeTV", $genre );
      AddCategory( $ce, $program_type, $category );
    }

    $dsh->AddProgramme( $ce );
  }

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate {
  my( $text ) = @_;
  my( $day , $month , $year );

print "DATEINFO: $text\n";
  return undef if( ! $text );

  if( $text =~ /^\d\d\/\d\d\/\d\d$/ ){
    ( $day , $month , $year ) = ( $text =~ /^(\d\d)\/(\d\d)\/(\d\d)$/ );
  } else {
    return undef;
  }

  $year += 2000 if $year lt 100;

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

sub ParseTime {
  my( $text ) = @_;

print "TIMEINFO: $text\n";
  return undef if ( $text !~ /^\d\d\:\d\d\:\d\d\s+(AM|PM)$/ );

  my( $hour, $min, $sec, $ampm ) = ( $text !~ /^(\d\d)\:(\d\d)\:(\d\d)\s+(\S+)$/ );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
