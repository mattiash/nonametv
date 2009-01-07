package NonameTV::Importer::Nickelodeon;

use strict;
use warnings;

=pod

Import data from Xls files delivered via e-mail.
Each day is handled as a separate batch.

Features:

=cut

use utf8;

use DateTime;
use Encode qw/encode decode/;
use XML::LibXML;
use Spreadsheet::ParseExcel;
use Archive::Zip;
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

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  if( $file =~ /\.xml$/i ){
    #$self->ImportXML( $file, $channel_id, $channel_xmltvid );
  } elsif( $file =~ /\.xls$/i ){
    $self->ImportXLS( $file, $channel_id, $channel_xmltvid );
  }

  return;
}

sub ImportXML
{
  my $self = shift;
  my( $file, $channel_id, $channel_xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_file($file); };

  if( not defined( $doc ) ) {
    error( "Nickelodeon XML: $file: Failed to parse xml" );
    return;
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

  progress( "Nickelodeon XLS: $channel_xmltvid: Processing XLS $file" );

  my( $oBook, $oWkS, $oWkC );
  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  if( not defined( $oBook ) ) {
    error( "Nickelodeon XLS: $file: Failed to parse xls" );
    return;
  }

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];

    if( $oWkS->{Name} !~ /Schedule Template/ ){
      progress("Nickelodeon XLS: $channel_xmltvid: skipping worksheet named '$oWkS->{Name}'");
      next;
    }

    progress("Nickelodeon XLS: $channel_xmltvid: processing worksheet named '$oWkS->{Name}'");

    # read the rows with data
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          if( $oWkS->{Cells}[$iR][$iC] ){
            $columns{$oWkS->{Cells}[$iR][$iC]->Value} = $iC;
          }
        }
foreach my $cl (%columns) {
print "$cl\n";
}
        next;
      }

      # Date
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Date'}];
      next if not $oWkC;
      next if not $oWkC->Value;
      $date = ParseDate( $oWkC->Value );
      next if not $date;

      if( $date ne $currdate ) {
        if( $currdate ne "x" ) {
	  $dsh->EndBatch( 1 );
        }

        my $batch_id = $channel_xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;

        progress("Nickelodeon XLS: $channel_xmltvid: Date is: $date");
      }

      # Time
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Start time CET'}];
      next if not $oWkC;
      next if not $oWkC->Value;
      my $time = ParseTime( $oWkC->Value );
      next if not $time;

      # Title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Programme Title'}];
      next if( ! $oWkC );
      my $title = $oWkC->Value;
      next if not $title;

      my $rating = $oWkS->{Cells}[$iR][$columns{'PG Rating'}]->Value if $oWkS->{Cells}[$iR][$columns{'PG Rating'}];
      my $cencod = $oWkS->{Cells}[$iR][$columns{'Censorship Codes'}]->Value if $oWkS->{Cells}[$iR][$columns{'Censorship Codes'}];
      my $websyn = $oWkS->{Cells}[$iR][$columns{'Website Synopsis'}]->Value if $oWkS->{Cells}[$iR][$columns{'Website Synopsis'}];
      my $epgsyn = $oWkS->{Cells}[$iR][$columns{'EPG Synopsis'}]->Value if $oWkS->{Cells}[$iR][$columns{'EPG Synopsis'}];
      my $mobsyn = $oWkS->{Cells}[$iR][$columns{'Mobile Synopsis'}]->Value if $oWkS->{Cells}[$iR][$columns{'Mobile Synopsis'}];
      my $epitit = $oWkS->{Cells}[$iR][$columns{'Episode Title'}]->Value if $oWkS->{Cells}[$iR][$columns{'Episode Title'}];
      my $epinum = $oWkS->{Cells}[$iR][$columns{'Episode Number'}]->Value if $oWkS->{Cells}[$iR][$columns{'Episode Number'}];
      my $seanum = $oWkS->{Cells}[$iR][$columns{'Season Number'}]->Value if $oWkS->{Cells}[$iR][$columns{'Season Number'}];
      my $seaepi = $oWkS->{Cells}[$iR][$columns{'Number of episodes in the Season'}]->Value if $oWkS->{Cells}[$iR][$columns{'Number of episodes in the Season'}];
      my $seastart = $oWkS->{Cells}[$iR][$columns{'Start of Season'}]->Value if $oWkS->{Cells}[$iR][$columns{'Start of Season'}];
      my $seaend = $oWkS->{Cells}[$iR][$columns{'End of Season'}]->Value if $oWkS->{Cells}[$iR][$columns{'End of Season'}];
      my $theme = $oWkS->{Cells}[$iR][$columns{'Theme'}]->Value if $oWkS->{Cells}[$iR][$columns{'Theme'}];
      my $live = $oWkS->{Cells}[$iR][$columns{'Live'}]->Value if $oWkS->{Cells}[$iR][$columns{'Live'}];
      my $relyear = $oWkS->{Cells}[$iR][$columns{'Year Of Release'}]->Value if $oWkS->{Cells}[$iR][$columns{'Year Of Release'}];
      my $actors = $oWkS->{Cells}[$iR][$columns{'Acrors'}]->Value if $oWkS->{Cells}[$iR][$columns{'Acrors'}];
      my $directors = $oWkS->{Cells}[$iR][$columns{'Director/s'}]->Value if $oWkS->{Cells}[$iR][$columns{'Director/s'}];
      my $awards = $oWkS->{Cells}[$iR][$columns{'Awards'}]->Value if $oWkS->{Cells}[$iR][$columns{'Awards'}];
      my $hisubs = $oWkS->{Cells}[$iR][$columns{'HI Subtitles'}]->Value if $oWkS->{Cells}[$iR][$columns{'HI Subtitles'}];
      my $subs = $oWkS->{Cells}[$iR][$columns{'Subtitles'}]->Value if $oWkS->{Cells}[$iR][$columns{'Subtitles'}];
      my $premiere = $oWkS->{Cells}[$iR][$columns{'Premiere'}]->Value if $oWkS->{Cells}[$iR][$columns{'Premiere'}];
      my $highlight = $oWkS->{Cells}[$iR][$columns{'Highlight'}]->Value if $oWkS->{Cells}[$iR][$columns{'Highlight'}];
      my $changealert = $oWkS->{Cells}[$iR][$columns{'Change Alert'}]->Value if $oWkS->{Cells}[$iR][$columns{'Change Alert'}];
      my $format = $oWkS->{Cells}[$iR][$columns{'16:9 Format (widescreen)'}]->Value if $oWkS->{Cells}[$iR][$columns{'16:9 Format (widescreen)'}];
      my $hd = $oWkS->{Cells}[$iR][$columns{'High Definition'}]->Value if $oWkS->{Cells}[$iR][$columns{'High Definition'}];
      my $dolby = $oWkS->{Cells}[$iR][$columns{'Dolby Digital'}]->Value if $oWkS->{Cells}[$iR][$columns{'Dolby Digital'}];
      my $stereo = $oWkS->{Cells}[$iR][$columns{'Stereo'}]->Value if $oWkS->{Cells}[$iR][$columns{'Stereo'}];
      my $surround = $oWkS->{Cells}[$iR][$columns{'Surround Sound'}]->Value if $oWkS->{Cells}[$iR][$columns{'Surround Sound'}];

      progress( "Nickelodeon XLS: $channel_xmltvid: $time - $title" );

      my $ce = {
        channel_id => $channel_id,
        title => $title,
        start_time => $time,
      };

      $ce->{description} = $epgsyn if $epgsyn;

      $ce->{subtitle} = $epitit if $epitit;

      if( $epinum ){
        if( $seanum ){
          $ce->{episode} = sprintf( "%d . %d .", $seanum-1, $epinum-1 );
        } else {
          $ce->{episode} = sprintf( ". %d .", $epinum-1 );
        }
      }

      $ce->{aspect} = $format ? "16:9" : "4:3";
      $ce->{stereo} = $stereo if $stereo;
      $ce->{rating} = $rating if $rating;
      $ce->{directors} = $directors if $directors;
      $ce->{actors} = $actors if $actors;

      $dsh->AddProgramme( $ce );

    } # next row

    %columns = ();

  } # next worksheet

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate {
  my( $dateinfo ) = @_;

  my( $year, $month, $day );

  # format: '20090201'
  if( $dateinfo =~ /^\d{8}$/ ){
    ( $year, $month, $day ) = ( $dateinfo =~ /^(\d{4})(\d{2})(\d{2})$/ );
  }

  return sprintf( "%04d-%02d-%02d", $year, $month, $day );
}

sub ParseTime {
  my( $timeinfo ) = @_;

  my( $hour, $min );

  # format: '20090201'
  if( $timeinfo =~ /^\d{4}$/ ){
    ( $hour, $min ) = ( $timeinfo =~ /^(\d{2})(\d{2})$/ );
  }

  $hour -= 24 if $hour > 23;

  return sprintf( "%02d:%02d", $hour, $min );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
