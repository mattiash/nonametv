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
                                         { grabber => 'expressen' },
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
    progress( "Expressen: Processing $file" );
    $self->ImportFile( "", $file, $p );
  } 
}

sub ImportFile
{
  my $self = shift;
  my( $contentname, $file, $p ) = @_;

  # We only support one channel for Expressen.
  my $xmltvid="sport.expressen.se";

  my $channel_id = $self->{channel_data}->{$xmltvid}->{id};
  
  my $dsh = $self->{datastorehelper};
  
  my $doc;
  if( $file =~  /\.doc$/ )
  {
    $doc = Wordfile2Xml( $file );
  }

  # It may be a html-file even though it is called .doc...
  if( not defined $doc )
  {
    $doc = Htmlfile2Xml( $file );
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
          $dsh->EndBatch( 1, log_to_string_result( $loghandle ) );
        }

        ($date) = ($day =~ /(\d\d\d\d-\d\d-\d\d)/)
          or logdie "Invalid day $day";

        $loghandle = log_to_string( 4 );
        $dsh->StartBatch( "${xmltvid}_$date", $channel_id );
        $dsh->StartDate( $date );
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
    $dsh->EndBatch( 1, log_to_string_result( $loghandle ) );
  }
  
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
