package NonameTV::Importer::RMTV;

use strict;
use warnings;

=pod

Import data from Excel files delivered via e-mail.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;
use Spreadsheet::XLSX;
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

  $self->{grabber_name} = "RMTV";

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

  if( $file =~ /\.xlsx$/i ){
    $self->ImportXLSX( $file, $channel_id, $xmltvid );
  } elsif( $file =~ /\.xls$/i ){
    $self->ImportXLS( $file, $channel_id, $xmltvid );
  }

  return;
}

sub ImportXLSX
{
  my $self = shift;
  my( $file, $channel_id, $xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  return if( $file !~ /\.xlsx$/i );
  progress( "RMTV XLSx: $xmltvid: Processing $file" );

  my %columns = ();
  my $date;
  my $currdate = undef;

  my $excel = Spreadsheet::XLSX->new ( $file );

  foreach my $sheet (@{$excel->{Worksheet}}){

    progress( "RMTV XLSx: $xmltvid: Processing worksheet: $sheet->{Name}" );

    $sheet->{MaxRow} ||= $sheet->{MinRow};

    foreach my $row ($sheet->{MinRow} .. $sheet->{MaxRow}){

      $sheet->{MaxCol} ||= $sheet->{MinCol};

      foreach my $col ($sheet->{MinCol} .. $sheet->{MaxCol}){
        my $cell = $sheet->{Cells}[$row][$col];
#if( $cell ){
#print $row . " - " . $col . " - " . $cell->{Val} . "\n";
#} else {
#print $row . " - " . $col . "\n";
#}
      }

      # get the date
      # from column 0
#      my $cell = $sheet->{Cells}[$row][0];
#      if( $cell ){
#print $row . " - " . $cell->{Val} . "\n";

#        if( isDate( $cell->{Val} ) ){

#          if( $date = ParseDate( $cell->{Val} ) ){
#print "DATUM: $date\n";

#            $dsh->EndBatch( 1 ) if defined $currdate;

#            my $batch_id = "${xmltvid}_" . $date;
#            $dsh->StartBatch( $batch_id, $channel_id );
#            $dsh->StartDate( $date , "00:00" );
#            $currdate = $date;

#            progress("RMTV XLS: Date is $date");

#            # after each row with the date
#            # comes the one with column names
#            %columns = ();

#            next;
#          }
#        }
#      }
    }

  }

  return;
}

sub ImportXLS
{
  my $self = shift;
  my( $file, $channel_id, $xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

return;

  return if( $file !~ /\.xls$/i );
  progress( "RMTV XLS: $xmltvid: Processing $file" );

  my %columns = ();
  my $date;
  my $currdate = undef;

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress( "RMTV XLS: $xmltvid: Processing worksheet: $oWkS->{Name}" );

    # browse through rows
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # get the date
      # from column 0
      if( $oWkS->{Cells}[$iR][0] ){

        if( isDate( $oWkS->{Cells}[$iR][0]->Value ) ){

          if( $date = ParseDate( $oWkS->{Cells}[$iR][0]->Value ) ){

            $dsh->EndBatch( 1 ) if defined $currdate;

            my $batch_id = "${xmltvid}_" . $date;
            $dsh->StartBatch( $batch_id, $channel_id );
            $dsh->StartDate( $date , "00:00" );
            $currdate = $date;

            progress("RMTV XLS: Date is $date");

            # after each row with the date
            # comes the one with column names
            %columns = ();

            next;
          }
        }
      }

      # get the names of the columns from the 1st row
      if( $date and not %columns ){
        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          if( $oWkS->{Cells}[$iR][$iC] ){
            $columns{norm($oWkS->{Cells}[$iR][$iC]->Value)} = $iC;
          }
        }
#foreach my $cl (%columns) {
#print "$cl\n";
#}
        next;
      }

      # we have to skip first few rows
      # until we find the one with the date
      next if not $date;

      my $oWkC;

      # time - column 'TIME CEST'
      $oWkC = $oWkS->{Cells}[$iR][$columns{'TIME CEST'}];
      next if( ! $oWkC );
      my $time = $oWkC->Value if( $oWkC->Value );
      $time =~ s/^24\:/0:/; 

      # title - column 'PROGRAMME'
      $oWkC = $oWkS->{Cells}[$iR][$columns{'PROGRAMME'}];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );

      # synopsis - column 'WEB SYNOPSIS'
      $oWkC = $oWkS->{Cells}[$iR][$columns{'WEB SYNOPSIS'}];
      my $synopsis = $oWkC->Value if( $oWkC->Value );

      # duration - column 'DUR'
      $oWkC = $oWkS->{Cells}[$iR][$columns{'DUR'}];
      my $duration = $oWkC->Value if( $oWkC->Value );

      # ref - column 'RMTV REF'
      $oWkC = $oWkS->{Cells}[$iR][$columns{'RMTV REF'}];
      my $ref = $oWkC->Value if( $oWkC->Value );

      progress("RMTV XLS: $xmltvid: $time - $title");

      my $ce = {
        channel_id => $channel_id,
        title => $title,
        start_time => $time,
      };

      $ce->{subtitle} = $ref if $ref;
      $ce->{description} = $synopsis if $synopsis;

      $dsh->AddProgramme( $ce );
    }
  }

  $dsh->EndBatch( 1 );

  return;
}

sub isDate {
  my( $text ) = @_;

print "TXT: $text\n";
  return 0 if( ! $text );

  # the format is 'Saturday, 7 June 2008'
  # or may be also 'Friday, 13th June 2008'
  # or without the ',' like 'Tuesday 10th June 2008'
  if( $text =~ /^(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\,*\s*\d+\S*\s+\S+\s+\d+$/i ){
    return 1;
  }

  return 0;
}

sub ParseDate {
  my( $text ) = @_;

print "TXT: $text\n";
  return undef if( ! $text );

  if( $text =~ /^(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\,*\s*\d+\S*\s+\S+\s+\d+$/i ){

    my( $dayname, $day, $monthname, $year ) = ( $text =~ /^(\S+)\,*\s*(\d+)\S*\s+(\S+)\s+(\d+)$/i );

    my @months_eng = qw/january february march april may june july august september october november december/;
    my %monthnames = ();
    for( my $i = 0; $i < scalar(@months_eng); $i++ )
      { $monthnames{$months_eng[$i]} = $i+1;}

    my $month = $monthnames{lc $monthname};

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
