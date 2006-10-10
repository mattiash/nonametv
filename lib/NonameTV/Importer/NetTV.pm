package NonameTV::Importer::NetTV;

use strict;
use warnings;

=pod

Import data from Excel-files delivered via e-mail.

Features:

=cut

use utf8;

use POSIX qw/strftime/;
use DateTime;
use Spreadsheet::ParseExcel;

use NonameTV::DataStore::Helper;
use NonameTV::Log qw/info progress error logdie 
                     log_to_string log_to_string_result/;
use NonameTV qw/AddCategory norm/;

use NonameTV::Importer;

use base 'NonameTV::Importer';

sub new 
{
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);
  
  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  my $sth = $self->{datastore}->Iterate( 'channels', 
                                         { grabber => 'NetTV' },
                                         qw/xmltvid id grabber_info/ )
    or logdie "Failed to fetch grabber data";

  while( my $data = $sth->fetchrow_hashref )
  {
    $self->{channel_data}->{$data->{xmltvid}} = 
                            { id => $data->{id}, };
  }

  $sth->finish;

    $self->{OptionSpec} = [ qw/verbose/ ];
    $self->{OptionDefaults} = { 
      'verbose'      => 0,
    };

  return $self;
}

sub Import
{
  my $self = shift;
  my( $p ) = @_;

  foreach my $file (@ARGV)
  {
    progress( "NetTV: Processing $file" );
    $self->ImportFile( "", $file, $p );
  } 
}

sub ImportFile
{
  my $self = shift;
  my( $contentname, $file, $p ) = @_;

  # We only support one channel for NetTV.
  my $xmltvid="nettv.tv.gonix.net";

  my $channel_id = $self->{channel_data}->{$xmltvid}->{id};
  
  my $dsh = $self->{datastorehelper};
  
  # Only process .xls-files.
  return if $file !~  /\.xls$/i;

  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;

  $ds->StartBatch( $xmltvid , $channel_id );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse($file);

  my($iR, $oWkS, $oWkC);

  # There are 2 Worksheets in the xls file
  # The name of the sheet that contains schedule is PPxle

  # The columns in the xls file are:
  # --------------------------------
  # kada - date and time
  # ime emisije - title
  # vrsta emisije - genre
  # epizoda - episode number
  # p/r - premiere or retransmission

  foreach my $oWkS (@{$oBook->{Worksheet}}) {
    print "--------- SHEET:", $oWkS->{Name}, "\n";

    # the schedule is inside of the sheet named "PPxle"
    next if $oWkS->{Name} ne "PPxle";

    print "processing sheet: $oWkS->{Name}\n";

    my ( $day , $month , $year , $hour , $min );
    my ( $newtime , $lasttime );
    my ( $title , $genre , $episode , $premiere );

    # process xls
    for(my $iR = 0 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # field "kada" (column 0)
      $oWkC = $oWkS->{Cells}[$iR][0];
      my $kada = $oWkC->Value;

      my( $a , $b , $c ) = split( '\.' , $kada );

      if( $c ne undef ){ # we are on the row with date
        $day = $a;
        $month = $b;
        $year = $c;
        $hour = undef;
        $min = undef;
      } elsif( $year ne undef ){
        $hour = $a;
        $min = $b;
      }

      if( $hour ne undef ){
        $newtime = create_dt( $day , $month , $year , $hour , $min );
      }

        # we are on next row already
        # write the previous row now as we stil have data from previous row loaded in variables

        if( defined( $lasttime ) and defined( $newtime ) ){
          my $ce = {
            channel_id   => $channel_id,
            start_time   => $lasttime->ymd("-") . " " . $lasttime->hms(":"), 
            end_time     => $newtime->ymd("-") . " " . $newtime->hms(":"),
            title        => norm($title),
          };
  
          if( defined( $episode ) )
          {
            $ce->{episode} = norm($episode);
            #$ce->{program_type} = 'series';
          }

          if( defined( $genre ) )
          {
            my($program_type, $category ) = $ds->LookupCat( "NetTV", $genre );
      
            AddCategory( $ce, $program_type, $category );

          }

          $ds->AddProgramme( $ce );
        }

      # field "ime emisije" (column 1)
      $oWkC = $oWkS->{Cells}[$iR][1];
      $title = $oWkC->Value;

      # field "vrsta emisije" (column 2)
      $oWkC = $oWkS->{Cells}[$iR][2];
      $genre = $oWkC->Value;

      # field "epizoda" (column 3)
      $oWkC = $oWkS->{Cells}[$iR][3];
      $episode = $oWkC->Value;

      # field "premiere/replay" (column 4)
      $oWkC = $oWkS->{Cells}[$iR][4];
      $premiere = $oWkC->Value;

      if( defined( $newtime ) ){
        $lasttime = $newtime;
      }

    }
  }

  my $date = undef;
  my $loghandle;
 
 $dsh->EndBatch( 1, log_to_string_result( $loghandle ) );
}

sub create_dt
{
  my ( $day , $month , $year , $hour , $min ) = @_;

  my $dt = DateTime->new( year   => $year,
                           month  => $month,
                           day    => $day,
                           hour   => $hour,
                           minute => $min,
                           second => 0,
                           time_zone => 'Europe/Zagreb',
                           ); 
  # times are in CET timezone in original XLS file
  $dt->set_time_zone( "UTC" );
  
  return( $dt );
}

sub extract_extra_info
{
  my( $ce ) = shift;

  if( $ce->{title} =~ /^slut$/i )
  {
    $ce->{title} = "end-of-transmission";
  }

  return;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
