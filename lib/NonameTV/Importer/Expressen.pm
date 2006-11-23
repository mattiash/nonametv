package NonameTV::Importer::Expressen;

use strict;
use warnings;

=pod

Import data from Word-files delivered via e-mail. The parsing of the
data relies on data being presented in one table per day. Each day
is handled as a separate batch.

Features:

=cut

use utf8;

use DateTime;
use XML::LibXML;

use NonameTV qw/MyGet Wordfile2Xml Htmlfile2Xml norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/info progress error logdie 
                     log_to_string log_to_string_result/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new 
{
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  $self->{grabber_name} = "Expressen";

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile
{
  my $self = shift;
  my( $file, $chd ) = @_;

  progress( "Expressen: Processing $file" );
  
  $self->{fileerror} = 0;

  # We only support one channel for Expressen.
  my $xmltvid=$chd->{xmltvid};

  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  
  # Only process .doc-files.
  if( $file !~  /\.doc$/i ) {
    error("SportExpressen: $file is not a word-file.");
    return;
  }
 
  # It may be a html-file even though it is called .doc...
  my $doc = Htmlfile2Xml( $file );
  
  if( not defined( $doc ) )
  {
    $doc = Wordfile2Xml( $file );
  }
  
  if( not defined( $doc ) )
  {
    error( "Expressen: $file failed to parse" );
    return;
  }
  
  # Find all table-entries.
  my $ns = $doc->find( "//table" );
  
  if( $ns->size() == 0 )
  {
    error( "Expressen: $file: No tables found." ) ;
    return;
  }

  my $date = undef;
  my $loghandle;

  foreach my $table ($ns->get_nodelist)
  {
    my $ns2 = $table->find( ".//tr" );
    
    foreach my $tr ($ns2->get_nodelist)
    {
      my $time = norm( $tr->findvalue( './/td[1]//text()' ) );

      next if( $time !~ /\S.*\S/ );

      next if $time =~ /^\s*Vecka\s*\d+(\s*version\s*\d+)*\s*$/i;

      if( $time =~ /^mån|tis|ons|tor|fre|lör|sön|\d\d\d\d-\d\d-\d\d/i )
      {
        # Sometimes there is a weekday in the first column and a date in
        # the second, sometimes they are both in the first column.
        # Sometimes there is no weekday, only a date.
        my $day = norm( $tr->findvalue( './/td[1]//text()' ) ) . " " . 
          norm( $tr->findvalue( './/td[2]//text()' ) );

        if( defined( $date ) )
        {
          $dsh->EndBatch( 1 );
        }

        ($date) = ($day =~ /(\d\d\d\d-\d\d-\d\d)/)
          or logdie "Invalid day $day";

        $dsh->StartBatch( "${xmltvid}_$date", $channel_id );
        $dsh->StartDate( $date );
        $self->AddDate( $date );
        progress( "${xmltvid}_$date: Processing $file." );
        next;
      }

      my $title = norm( $tr->findvalue( './/td[2]//text()' ) );
      my $description = norm( $tr->findvalue( './/td[3]//text()' ) );

      $time =~ tr/\.o/:0/;
      $time =~ tr/ \t//d;

      # Replace strange character representing a minus.
      $time =~ tr/\x{2013}/-/;

      my( $starttime, $endtime ) = split( "-", $time);

      if( $starttime !~ /^\d{1,2}:\d{1,2}$/ )
      {
        error( "$file: Ignoring starttime $starttime" );
        next;
      }

      if( defined( $endtime ) and $endtime =~ /^\s*$/ ) {
        $endtime = undef;
      }

      if( defined( $endtime ) and $endtime !~ /^\d{1,2}:\d{1,2}$/ )
      {
        error( "$file: Unknown endtime $endtime" );
        next;
      }

      my $ce = {
        title       => $title,
        start_time  => $starttime,
      };

      $ce->{end_time} = $endtime 
        if defined $endtime;

      # Some descriptions just contain a single non-alpha character.
      $ce->{description} = $description 
        if( $description =~ /[a-z]/ );

      extract_extra_info( $ce );

      $dsh->AddProgramme( $ce );
    }
  }
 
  if( defined( $date ) )
  {
    $dsh->EndBatch( 1 );
  }

  return;
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
