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

use NonameTV qw/norm AddCategory MonthNumber/;
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
#foreach my $col (%columns) {
#print ">$col<\n";
#}
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
      $subtitle = $oWkS->{Cells}[$iR][3]->Value if $oWkS->{Cells}[$iR][3];

      # description - column 4 ('PRESSE UK')
      $description = $oWkS->{Cells}[$iR][$columns{'PRESSE UK'}]->Value if $oWkS->{Cells}[$iR][$columns{'PRESSE UK'}];

      progress("Motors: $xmltvid: $time - $title");

      my $ce = {
        channel_id => $channel_id,
        title => $title,
        start_time => $time,
      };

      $ce->{subtitle} = $subtitle if $subtitle;
      $ce->{description} = $description if $description;

      $dsh->AddProgramme( $ce );
    }
  }

  $dsh->EndBatch( 1 );

  return;
}


sub ParseDate {
  my( $text ) = @_;

#print ">$text<\n";

  return undef if( ! $text );

  # Format 'VENDREDI 27 FAVRIER   2009'
  if( $text =~ /\S+\s+\d\d\s\S+\s+\d\d\d\d/ ){

    my( $dayname, $day, $monthname, $year ) = ( $text =~ /(\S+)\s+(\d\d)\s(\S+)\s+(\d\d\d\d)/ );
#print "$dayname\n";
#print "$day\n";
#print "$monthname\n";
#print "$year\n";

    $year += 2000 if $year lt 100;

    my $month = MonthNumber( $monthname, 'fr' );
#print "$month\n";

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
