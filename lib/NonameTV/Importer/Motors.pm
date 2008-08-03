package NonameTV::Importer::Motors;

use strict;
use warnings;

=pod

Import data from Excel files delivered via e-mail.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;
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

  $self->{grabber_name} = "Motors";

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

  return if( $file !~ /\.xls$/i );
  progress( "Motors: $xmltvid: Processing $file" );

  my %columns = ();
  my $date;
  my $currdate = undef;

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress( "Motors: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

    # browse through rows
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # get the names of the columns from the 1st row
      if( not %columns ){
        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          $columns{$oWkS->{Cells}[$iR][$iC]->Value} = $iC;
        }
        next;
      }

      # date - column 0 ('Date de diffusion')
      my $oWkC = $oWkS->{Cells}[$iR]['Date de diffusion'];
      if( $oWkC ){
        if( $date = ParseDate( $oWkC->Value ) ){

          $dsh->EndBatch( 1 ) if defined $currdate;

          my $batch_id = "${xmltvid}_" . $date;
          $dsh->StartBatch( $batch_id, $channel_id );
          $dsh->StartDate( $date , "05:00" );
          $currdate = $date;

          progress("Motors: Date is $date");

          next;
        }
      }

      # time - column 1 ('Horaire')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Horaire'}];
      next if( ! $oWkC );
      my $time = $oWkC->Value if( $oWkC->Value );

      # title - column 2 ('Titre du produit')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Titre du produit'}];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );

      my ( $subtitle, $description );

      # subtitle - column 3 ('Titre de l'ésode')
      $oWkC = $oWkS->{Cells}[$iR][3];
      if( $oWkC ){
        $subtitle = $oWkC->Value if( $oWkC->Value );
      }

      # description - column 4 ('PRESSE UK')
      $oWkC = $oWkS->{Cells}[$iR][$columns{'PRESSE UK'}];
      if( $oWkC ){
        $description = $oWkC->Value if( $oWkC->Value );
      }

      progress("Motors: $xmltvid: $time - $title");

      my $ce = {
        channel_id => $channel_id,
        title => $title,
        subtitle => $subtitle,
        start_time => $time,
        description => $description,
      };

      $dsh->AddProgramme( $ce );
    }
  }

  $dsh->EndBatch( 1 );

  return;
}


sub ParseDate {
  my( $text ) = @_;

  return undef if( ! $text );

  if( $text =~ /\S+\s+\d\d\s\S+\s+\d\d\d\d/ ){

    my( $dayname, $day, $monthname, $year ) = ( $text =~ /(\S+)\s+(\d\d)\s(\S+)\s+(\d\d\d\d)/ );

    my $month;
    $month = 1 if( $monthname =~ /janvier/i );
    $month = 2 if( $monthname =~ /féier/i );
    $month = 3 if( $monthname =~ /mars/i );
    $month = 4 if( $monthname =~ /avril/i );
    $month = 5 if( $monthname =~ /mai/i );
    $month = 6 if( $monthname =~ /juin/i );
    $month = 7 if( $monthname =~ /juillet/i );
    $month = 8 if( $monthname =~ /AOÛT/i);
    $month = 9 if( $monthname =~ /septembre/i );
    $month = 10 if( $monthname =~ /octobre/i );
    $month = 11 if( $monthname =~ /novembre/i );
    $month = 12 if( $monthname =~ /démbre/i );
$month = 8 if !$month;

    my $date = sprintf( "%04d-%02d-%02d", $year, $month, $day );
    return $date;
  }

  return undef;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
