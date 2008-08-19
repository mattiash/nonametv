package NonameTV::Importer::DisneyChannel;

use strict;
use warnings;

=pod

Import data from Xml-files delivered via e-mail in zip-files.  Each
day is handled as a separate batch.

Features:

=cut

use utf8;

use DateTime;
use XML::LibXML;
use Archive::Zip;
use Data::Dumper;
use File::Temp qw/tempfile/;

use NonameTV qw/norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error 
                     log_to_string log_to_string_result/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  $self->{grabber_name} = "DisneyChannel";

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  progress( "DisneyChannel: Processing $file" );
  
  $self->{fileerror} = 0;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $ds = $self->{datastore};

  my $datafile;

  if( $file =~ /\.xml$/i ) {
    $datafile = $file;
  }
  elsif( $file =~ /\.zip$/i ) {
    my $zip = Archive::Zip->new( $file );
    if( not defined $zip ) {
      error( "DisneyChannel $file: Failed to read zip." );
      return;
    }

    my @swedish_files;
    
    my @members = $zip->members();
    foreach my $member (@members) {
      push( @swedish_files, $member->{fileName} ) 
	  if $member->{fileName} =~ /swed.*xml$/i;
    }
    
    my $numfiles = scalar( @swedish_files );
    if( $numfiles != 1 ) {
      error( "DisneyChannel $file: Found $numfiles matching files, expected 1." );
      return;
    }

    progress( "Using file $swedish_files[0]" );

    (undef, $datafile) = tempfile();
    
    $zip->extractMember( $swedish_files[0], $datafile );
  }

  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_file($datafile); };

  if( not defined( $doc ) ) {
    error( "DisneyChannel $file: Failed to parse xml" );
    return;
  }

  my $ns = $doc->find( "//ss:Row" );
  
  if( $ns->size() == 0 ) {
    error( "DisneyChannel $file: No Rows found." ) ;
    return;
  }

  my $batch_id;

  my $currdate = "x";
  my $column;

  foreach my $row ($ns->get_nodelist) {
    if( not defined( $column ) ) {
      # This is the first row. Check where the columns are.
      my $ns2 = $row->find( ".//ss:Cell" );
      my $i = 1;
      $column = {};
      foreach my $cell ($ns2->get_nodelist) {
	my $v = $cell->findvalue( "." );
	$column->{$v} = "ss:Cell[$i]";
	$i++;
      }

      # Check that we found the necessary columns.

      next;
    }

    my $orgdate = norm( $row->findvalue( $column->{Date} ) );
    my $orgstarttime = norm( $row->findvalue( $column->{Time} ) );
    my $title = norm( $row->findvalue( $column->{"(SWE) Title"} ) );
    my $synopsis = norm( $row->findvalue( $column->{SYNOPSIS} ) );

    my( $year, $month, $day ) = ParseDate( $orgdate );
    if( not defined $day ) {
      error( "DisneyChannel $file: Invalid date $orgdate" );
      next;
    }
    my $date = sprintf( "%4d-%02d-%02d", $year, $month, $day );

    my( $hour, $minute ) = ParseTime( $orgstarttime );
    if( not defined $minute ) {
      error( "DisneyChannel $file: Invalid time $orgstarttime" );
      next;
    }
    my $starttime = sprintf( "%02d:%02d", $hour, $minute );
      
    if( $date ne $currdate ) {
      if( $currdate ne "x" ) {
	$ds->EndBatch( 1 );
      }

      my $batch_id = $xmltvid . "_" . $date;
      $ds->StartBatch( $batch_id );
      $currdate = $date;
    }

    my $start_dt = $self->to_utc( $date, $starttime );

    if( not defined( $start_dt ) ) {
      error( "Invalid start-time '$date' '$starttime'. Skipping." );
      next;
    }

    my $ce = {
      channel_id => $channel_id,
      title => $title,
      description => $synopsis,
      start_time => $start_dt->ymd('-') . " " . $start_dt->hms(':'),
    };
    
    $ds->AddProgramme( $ce );
  }

  $ds->EndBatch( 1 );
    
  return;
}

sub ParseDate {
  my( $text ) = @_;

  my( $day, $month, $year ) = ($text =~ m%^(\d\d)/(\d\d)/(\d\d\d\d)$% );
  
  if( not defined( $year ) ) {
    # This might be a DateTime string instead.
    ( $year, $month, $day ) = ( $text =~ /^(\d{4})-(\d{2})-(\d{2})T\d\d:\d\d:/ );
  }

  if( not defined( $year ) ) {
    return undef;
  }

  return ($year,$month,$day);
}

sub ParseTime {
  my( $text ) = @_;

  my( $hour, $minute ) = ($text =~ m%^(\d\d):(\d\d)$% );
  
  if( not defined( $minute ) ) {
    # This might be a DateTime string instead.
    ( $hour, $minute ) = ( $text =~ /^\d{4}-\d{2}-\d{2}T(\d\d):(\d\d):/ );
  }
  
  if( not defined( $minute ) ) {  
    return undef;
  }

  return ($hour, $minute);
}

sub to_utc {
  my $self = shift;
  my( $date, $time ) = @_;

  my( $year, $month, $day ) = split( "-", $date );
  
  my( $hour, $minute ) = split( ":", $time );

  my $dt;

  my $add = 0;
  if( $hour > 23 ) {
    $hour -= 24;
    $add = 1;
  }

  eval { 
    $dt = DateTime->new( year   => $year,
			 month  => $month,
			 day    => $day,
			 hour   => $hour,
			 minute => $minute,
			 time_zone => 'Europe/Stockholm',
			 );
  };

  if( not defined $dt ) {
    return undef;
  }

  if( $add ) {
    $dt->add( hours => 24 );
  }

  $dt->set_time_zone( "UTC" );

  return $dt;
}
  
1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
