package NonameTV::Importer::ZoneClub;

use strict;
use warnings;

=pod

Import data from XLS files delivered via e-mail.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;
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

  # Only process .xls files.
  return if( $file !~ /\.xls$/i );
  progress( "ZoneClub: $xmltvid: Processing $file" );

  my %columns = ();
  my $date;
  my $currdate = "x";

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];

    if( $oWkS->{Name} !~ /^English$/i ){
      progress( "ZoneClub: $chd->{xmltvid}: Skipping worksheet: $oWkS->{Name}" );
      next;
    }
    progress( "ZoneClub: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

    # browse through rows
    # schedules are starting after that
    # valid schedule row must have date, time and title set
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # get the names of the columns from the 1st row
      if( not %columns ){
        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          $columns{$oWkS->{Cells}[$iR][$iC]->Value} = $iC;
        }
#foreach my $cl (%columns) {
#print "$cl\n";
#}
        next;
      }

      my $oWkC;

      # date - column 'date'
      $oWkC = $oWkS->{Cells}[$iR][$columns{'schedule_date'}];
      next if( ! $oWkC );

      $date = ParseDate( $oWkC->Value );
      next if( ! $date );

      if( $date ne $currdate ){

        progress("ZoneClub: Date is $date");

        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;
      }

      # time - column 'start_time'
      $oWkC = $oWkS->{Cells}[$iR][$columns{'start_time'}];
      next if( ! $oWkC );
      my $time = $oWkC->Value if( $oWkC->Value );

      # duration - column 'duration'
      $oWkC = $oWkS->{Cells}[$iR][$columns{'duration'}];
      next if( ! $oWkC );
      my $duration = $oWkC->Value if( $oWkC->Value );

      # title - column 'event_title'
      $oWkC = $oWkS->{Cells}[$iR][$columns{'event_title'}];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );

      # rating - column 'Rating'
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Rating'}];
      next if( ! $oWkC );
      my $rating = $oWkC->Value if( $oWkC->Value );

      # episode_number - column 'ep Number'
      $oWkC = $oWkS->{Cells}[$iR][$columns{'ep Number'}];
      next if( ! $oWkC );
      my $episode_number = $oWkC->Value if( $oWkC->Value );

      # description - column 'event_short_description'
      $oWkC = $oWkS->{Cells}[$iR][$columns{'event_short_description'}];
      next if( ! $oWkC );
      my $description = $oWkC->Value if( $oWkC->Value );

      progress("ZoneClub: $xmltvid: $time - $title");

      my $ce = {
        channel_id => $channel_id,
        start_time => $time,
        title => norm($title),
      };

      $ce->{subtitle} = "Duration: $duration" if $duration;
      $ce->{description} = $description if $description;

      if( $episode_number )
      {
        $ce->{episode} = sprintf( ". %d .", $episode_number-1 );
      }

      $dsh->AddProgramme( $ce );
    }

    %columns = ();

  }

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my ( $dinfo ) = @_;

#print ">$dinfo<\n";

  my( $month, $day, $year ) = ( $dinfo =~ /(\d+)-(\d+)-(\d+)/ );

  return undef if( ! $year );

  $year += 2000 if $year < 100;

  return sprintf( "%04d-%02d-%02d", $year, $month, $day );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
