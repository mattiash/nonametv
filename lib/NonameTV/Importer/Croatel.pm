package NonameTV::Importer::Croatel;

use strict;
use warnings;

=pod

channels: SportKlub, SportKlub2, DoQ
country: Croatia

Import data from Excel-files delivered via e-mail.
Each file is for one week.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;

use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;
use NonameTV qw/AddCategory norm/;

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

  my $showtime = undef;
  my $title = undef;
  my $descr  = undef;
  my $currdate;
  my $today = DateTime->today();

  # Only process .xls files.
  return if $file !~  /\.xls$/i;

  progress( "Croatel: $chd->{xmltvid}: Processing $file" );

  $self->{fileerror} = 0;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];

    progress( "Croatel: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

    # The name of the sheet is the date in format DD.M.YYYY.
    my ( $date ) = ParseDate( $oWkS->{Name} );
    if( ! $date ){
      error( "Croatel: $chd->{xmltvid}: Invalid worksheet name: $oWkS->{Name} - skipping" );
      next;
    }

    if( defined $date ) {

      # skip the days in the past
      my $past = DateTime->compare( $date, $today );
      if( $past < 0 ){
        progress("Croatel: $chd->{xmltvid}: Skipping date $date");
        next;
      } else {
        progress("Croatel: $chd->{xmltvid}: Processing date $date");
      }
    }

    $dsh->EndBatch( 1 ) if defined $currdate;

    my $batch_id = "${xmltvid}_" . $date->ymd("-");
    $dsh->StartBatch( $batch_id, $channel_id );
    $dsh->StartDate( $date->ymd("-") , "05:00" );
    $currdate = $date;

    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # the show start time is in row1
      my $oWkC = $oWkS->{Cells}[$iR][1];
      next if not $oWkC;
      $showtime = $oWkC->Value;
      next if ( $showtime !~ /^(\d+)\:(\d+)$/ );

      # the show title is in row2
      $oWkC = $oWkS->{Cells}[$iR][2];
      next if not $oWkC;
      $title = $oWkC->Value;

      # the show description is in row3
      $oWkC = $oWkS->{Cells}[$iR][3];
      if( $oWkC ){
        $descr = $oWkC->Value;
      }

      my $starttime = create_dt( $date , $showtime );

      progress("Croatel: $chd->{xmltvid}: $starttime - $title");

      my $ce = {
        channel_id   => $chd->{id},
        start_time => $starttime->hms(":"),
        title => norm($title),
        description => norm($descr),
      };

      $dsh->AddProgramme( $ce );

      $showtime = undef;
      $title = undef;
      $descr = undef;

    } # next row

  } # next worksheet

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my ( $dinfo ) = @_;

  $dinfo =~ s/[ ]//g;

  my( $day, $mon, $yea ) = ( $dinfo =~ /(\d+)\.(\d+)\.(\d+)/ );
  if( ! $day or ! $mon or ! $yea ){
    return undef;
  }

  # there is an error in the file, so fix it
  $yea = 2008 if( $yea eq 3008 );

  my $dt = DateTime->new( year   => $yea,
                          month  => $mon,
                          day    => $day,
                          hour   => 0,
                          minute => 0,
                          second => 0,
                          time_zone => 'Europe/Zagreb',
  );

  return $dt;
}
  
sub create_dt
{
  my ( $dat , $tim ) = @_;

  my( $hr, $mn ) = ( $tim =~ /^(\d+)\:(\d+)$/ );

  my $dt = $dat->clone()->add( hours => $hr , minutes => $mn );

  if( $hr < 5 ){
    $dt->add( days => 1 );
  }

  return( $dt );
}
  
1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
