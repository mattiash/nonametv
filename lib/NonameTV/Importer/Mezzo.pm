package NonameTV::Importer::Mezzo;

use strict;
use warnings;

=pod

Importer for data from Mezzo Classic music channel. 
One file per month downloaded from LNI site.
The downloaded file is in xls format.

Features:

=cut

use POSIX qw/strftime/;
use DateTime;
use Spreadsheet::ParseExcel;

use NonameTV qw/MyGet norm AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;
use NonameTV::Config qw/ReadConfig/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);


  defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

  $self->{MinMonths} = 1 unless defined $self->{MinMonths};
  $self->{MaxMonths} = 12 unless defined $self->{MaxMonths};

  my $conf = ReadConfig();

  $self->{FileStore} = $conf->{FileStore};

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile
{
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  if( $file =~ /\.xls$/i ){
    $self->ImportXLS( $file, $channel_id, $channel_xmltvid );
  }

  return;
}

sub ImportXLS
{
  my $self = shift;
  my( $file, $channel_id, $channel_xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my %columns = ();
  my $date;
  my $currdate = "x";

  progress( "Mezzo: $channel_xmltvid: Processing XLS $file" );

  my( $oBook, $oWkS, $oWkC );
  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  if( not defined( $oBook ) ) {
    error( "Mezzo: $file: Failed to parse xls" );
    return;
  }

  if( not $oBook->{SheetCount} ){
    error( "Mezzo: $file: No worksheets found in file" );
    return;
  }

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];
    if( $oWkS->{Name} =~ /AM(\s+|\/)PM/ ){
      progress("Mezzo: $channel_xmltvid: Skipping worksheet named '$oWkS->{Name}'");
      next;
    }

    progress("Mezzo: $channel_xmltvid: Processing worksheet named '$oWkS->{Name}'");

    # read the rows with data
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {

          if( $oWkS->{Cells}[$iR][$iC] ){
            $columns{$oWkS->{Cells}[$iR][$iC]->Value} = $iC;

            # other possible names of the columns
            $columns{'DATE'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^DATES$/ );
            $columns{'TIME'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^TIMES$/ );
            $columns{'LENGTH'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^LENGHTS$/ );
            $columns{'TITLE'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^TITLES$/ );
            $columns{'DESCRIPTION'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^DESCRIPTIONS$/ );
          }

#foreach my $cl (%columns) {
#print "$cl\n";
#}
          next;
        }
      }

      # Date
      $oWkC = $oWkS->{Cells}[$iR][$columns{'DATE'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      $date = ParseDate( $oWkC->Value );
      next if( ! $date );

      if( $date ne $currdate ) {

        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $channel_xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;

        progress("Mezzo: $channel_xmltvid: Date is: $date");
      }

      
      # Time
      $oWkC = $oWkS->{Cells}[$iR][$columns{'TIME'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );

      my $time = ParseTime( $oWkC->Value );
      if( not defined( $time ) ) {
        error( "Invalid start-time '$date' '" . $oWkC->Value . "'. Skipping." );
        next;
      }

      # Length
      $oWkC = $oWkS->{Cells}[$iR][$columns{'LENGTH'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $duration = $oWkC->Value;

      # Title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'TITLE'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $title = $oWkC->Value;
      next if( ! $title );

      # Description
      $oWkC = $oWkS->{Cells}[$iR][$columns{'DESCRIPTION'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $description = $oWkC->Value;

      progress( "Mezzo: $channel_xmltvid: $time - $title" );

      my $ce = {
        channel_id => $channel_id,
        title => $title,
        start_time => $time,
      };

      $ce->{description} = $description if $description;

      $dsh->AddProgramme( $ce );

    } # next row

    %columns = ();

  } # next sheet

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate
{
  my( $dateinfo ) = @_;

  if( $dateinfo !~ /^\d+-\d+-\d+$/ ){
    return undef;
  }

  my( $month, $day, $year ) = ( $dateinfo =~ /^(\d+)-(\d+)-(\d+)$/ );

  $year += 2000 if( $year < 100);

  return sprintf( "%04d-%02d-%02d", $year, $month, $day );
}

sub ParseTime
{
  my( $timeinfo ) = @_;

  my( $hour, $min, $sec );

  if( $timeinfo =~ /^\d+:\d+:\d+$/ ){ # format '11:45:00'
    ( $hour, $min, $sec ) = ( $timeinfo =~ /^(\d+):(\d+):(\d+)$/ );
  } elsif( $timeinfo =~ /^\d+:\d+\s+AM\/PM$/ ){ # format '13:15 AM/PM'
    ( $hour, $min ) = ( $timeinfo =~ /^(\d+):(\d+)\s+AM\/PM$/ );
  } else {
    return undef;
  }

  return sprintf( "%02d:%02d", $hour, $min );
}

sub UpdateFiles {
  my( $self ) = @_;

  # get current month name
  my $year = DateTime->today->strftime( '%g' );

  # the url to fetch data from
  # is in the format http://www.lni.tv/lagardere-networks-international/uploads/media/Mezzo_Schedule_November_08.xls
  # UrlRoot = http://www.lni.tv/lagardere-networks-international/uploads/media/
  # GrabberInfo = <empty>

  foreach my $data ( @{$self->ListChannels()} ) {

    my $xmltvid = $data->{xmltvid};

    my $today = DateTime->today;

    # do it for MaxMonths in advance
    for(my $month=0; $month <= $self->{MaxMonths} ; $month++) {

      my $dt = $today->clone->add( months => $month );

      my ( $filename, $url );

      $filename = "Mezzo_Schedule_" . $dt->month_name . "_" . $dt->strftime( '%y' ) . ".xls";
      $url = $self->{UrlRoot} . "/" . $filename;
      progress("Mezzo: Fetching xls file from $url");
      ftp_get( $url, $self->{FileStore} . '/' .  $xmltvid . '/' . $filename );

      $filename = "Mezzo_Schedule_" . $dt->month_name . "_" . $dt->strftime( '%Y' ) . ".xls";
      $url = $self->{UrlRoot} . "/" . $filename;
      progress("Mezzo: Fetching xls file from $url");
      ftp_get( $url, $self->{FileStore} . '/' .  $xmltvid . '/' . $filename );
    }
  }
}

sub ftp_get {
  my( $url, $file ) = @_;

  qx[curl -S -s -z "$file" -o "$file" "$url"];
}

1;
