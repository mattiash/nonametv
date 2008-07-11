package NonameTV::Importer::MTVAdria;

use strict;
use warnings;

=pod

Channels: Slavonska TV Osijek

Import data from Word-files delivered via e-mail.  Each day
is handled as a separate batch.

Features:

=cut

use utf8;

use POSIX;
use DateTime;
use Locale::Recode;

use NonameTV qw/MyGet Wordfile2Xml Htmlfile2Xml norm AddCategory/;
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

  $self->{grabber_name} = "MTVAdria";

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile
{
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  
  return if( $file !~ /\.txt$/i );

  progress( "MTVAdria: $xmltvid: Processing $file" );
  
  open(TXTFILE, $file);
  my @lines = <TXTFILE>;

  my $currdate = "x";
  my $date = undef;
  my @ces;
  my $description;

  # the original file is in WINDOWS-1250 codepage
  my $cd = Locale::Recode->new( from => 'WINDOWS-1250' , to => 'UTF-8' );
#my $sup = Locale::Recode->getSupported;
#foreach my $s (@$sup){
#print $s . "\n";
#}

  foreach my $text (@lines){

#    if( not $cd->recode( $text ) ){
#      error("MTVAdria: $xmltvid: Failed to recode text");
#    }

    if( isDate( $text ) ) { # the line with the date in format 'Friday 1st August 2008'

      $date = ParseDate( $text );

      if( $date ) {

        progress("MTVAdria: $xmltvid: Date is $date");

        if( $date ne $currdate ) {

          if( $currdate ne "x" ){
            $dsh->EndBatch( 1 );
          }

          my $batch_id = "${xmltvid}_" . $date;
          $dsh->StartBatch( $batch_id, $channel_id );
          $dsh->StartDate( $date , "00:00" ); 
          $currdate = $date;
        }
      }

      # empty last day array
      undef @ces;
      undef $description;

    } elsif( isShow( $text ) ) {

      my( $time, $title ) = ParseShow( $text );

      # skip on error
      next if not $time;
      next if not $title;

      progress("MTVAdria: $xmltvid: $time - $title");

      my $ce = {
        channel_id => $chd->{id},
        start_time => $time,
        title => norm($title),
      };

      $dsh->AddProgramme( $ce );

    } else {
        # skip
    }
  }

  $dsh->EndBatch( 1 );

  close(TXTFILE);
    
  return;
}

sub isDate {
  my ( $text ) = @_;

  # format '2008-06-26 Thursday'
  if( $text =~ /^\s*\d+-\d+-\d+\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\s*$/i ){
    return 1;
  }

  return 0;
}

sub ParseDate {
  my( $text ) = @_;

  my( $year, $month, $day, $dayname ) = ( $text =~ /^\s*(\d+)-(\d+)-(\d+)\s+(\S+)\s*$/ );

  $year += 2000 if $year lt 2000;

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub isShow {
  my ( $text ) = @_;

  # format '21.40 Journal, emisija o modi (18)'
  if( $text =~ /^\d+\:\d+\s+.*$/i ){
    return 1;
  }

  return 0;
}

sub ParseShow {
  my( $text ) = @_;

  my( $hour, $min, $title );

  ( $hour, $min, $title ) = ( $text =~ /^(\d+)\:(\d+)\s+(.*)$/ );

  my $time = $hour . ":" . $min;
  $time = undef if( $min gt 59 );

  return( $time , $title );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
