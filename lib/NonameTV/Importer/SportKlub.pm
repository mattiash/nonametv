package NonameTV::Importer::SportKlub;

use strict;
use warnings;

=pod

channel: SportKlub and SportKlub2
country: Croatia

Import data from Excel-files delivered via e-mail.
Each file is for one week.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;

use NonameTV::DataStore::Helper;
use NonameTV::Log qw/info progress error logdie 
                     log_to_string log_to_string_result/;
use NonameTV qw/AddCategory norm/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  $self->{grabber_name} = "SportKlub";

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  my( $dateinfo );
  my( $kada, $newtime, $lasttime );
  my( $title, $newtitle , $lasttitle , $newdescription , $lastdescription );
  my( $hour , $min );

  # Only process .xls files.
  return if $file !~  /\.xls$/i;

  progress( "SportKlub: Processing $file" );

  $self->{fileerror} = 0;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my $batch_id = "${xmltvid}_" . DateTime->now();
  $dsh->StartBatch( $batch_id, $channel_id );
  $dsh->StartDate( DateTime->today->ymd("-") , "05:00" );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];

    progress( "SportKlub: Processing worksheet: $oWkS->{Name}" );

    # The name of the sheet is the date in format DD.M.YYYY.
    my ( $date ) = ParseDate( $oWkS->{Name} );

    if( defined $date ) {

      # skip the days in the past
      my $past = DateTime->compare_ignore_floating( $date, DateTime->today() );
      if( $past < 0 ){
        progress("SportKlub: Skipping date $date");
        next;
      } else {
        progress("SportKlub: Processing date $date");
      }
    }

    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # the show start time is in row1
      my $oWkC = $oWkS->{Cells}[$iR][1];
      next if not $oWkC;
      my $showtime = $oWkC->Value;

      next if ( $showtime !~ /^(\d+)\:(\d+)$/ );

      # the show title is in row2
      $oWkC = $oWkS->{Cells}[$iR][2];
      next if not $oWkC;
      my $title = $oWkC->Value;

      # the show description is in row3
      $oWkC = $oWkS->{Cells}[$iR][3];
      #next if not $oWkC;
      my $descr = $oWkC->Value;

      my $starttime = create_dt( $date , $showtime );

      progress("SportKlub: $chd->{xmltvid}: $starttime : $title");

      my $ce = {
        channel_id   => $chd->{id},
        start_time => $starttime->hms(":"),
        title => norm($title),
        description => norm($descr),
      };

      $dsh->AddProgramme( $ce );

    } # next column

  } # next worksheet

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my ( $dinfo ) = @_;

  $dinfo =~ s/[ ]//g;

  my( $day, $mon, $yea ) = ( $dinfo =~ /(\d+)\.(\d+)\.(\d+)/ );

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
