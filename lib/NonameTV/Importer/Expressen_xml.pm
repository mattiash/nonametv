package NonameTV::Importer::Expressen_xml;

use strict;
use warnings;

=pod

Import data from Xml-files delivered via e-mail. 

<chart>
  <week num="34">
     <day name="Måndag" date="2006-08-21">
       <program starttime="12:10" endtime="14:00" 
                sport="Fotboll" 
                magazinename="" 
                eventname="Spanska supercupen" 
                title="Barcelona - Espanyol">
         Från Camp Nou Stadium, Barcelona. Kommentator: Niklas Jarelind. Från 20/8.
       </program>

Features:

=cut

use utf8;

use DateTime;
use XML::LibXML;

use NonameTV qw/MyGet norm/;
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
#    $doc = Wordfile2Xml( $file );
  }
  elsif( $file =~ /\.xml$/ )
  {
    my $xml = XML::LibXML->new;
    eval { $doc = $xml->parse_string($$cref); };
    if( $@ ne "" )
    {
      error( "Expressen: $file failed to parse: $@" );
      return 0;
    }
  }

  if( not defined( $doc ) )
  {
    error( "Expressen: $file failed to parse" );
    return;
  }
  
  my $ns = $doc->find( "//day" );
  
  if( $ns->size() == 0 )
  {
    error( "Expressen: $file: No days found." ) ;
    return;
  }

  my $date = undef;
  my $loghandle;

  foreach my $day ($ns->get_nodelist)
  {
    my $date = norm( $day->findvalue( '@date' ) );

    if( $date !~ /^\d\d\d\d-\d\d-\d\d$/ )
    {
      error( "Expressen: $file contains unknown date $date. Skipping day." );
      next;
    }
    
    my $batch_id = "${xmltvid}_${date}";

    $dsh->StartBatch( $batch_id, $xmltvid );
    $dsh->StartDate( $date, "03:00" );

    my $ns2 = $day->find( ".//program" );
    
    foreach my $program ($ns2->get_nodelist)
    {
      my $starttime = norm( $program->findvalue( '@starttime' ) );
      my $endtime = norm( $program->findvalue( '@endtime' ) );
      my $sport = norm( $program->findvalue( '@sport' ) );
      my $magazinename = norm( $program->findvalue( '@magazinename' ) );
      my $eventname = norm( $program->findvalue( '@eventname' ) );
      my $title = norm( $program->findvalue( '@title' ) );
      my $desc = norm( $program->findvalue( 'text()' ) );

      $sport = undef if length( $sport ) = 0;
      $magazinename = undef if length( $magazinename ) = 0;
      $eventname = undef if length( $eventname ) = 0;
      $title = undef if length( $title ) = 0;

      if( defined( $magazinename ) )
      {
        error( "Expressen: $filename Program with both magazinename " .
               "and eventname" )
          if( defined( $eventname ) );

        $ce->{title} = norm( "$sport $magazinename" );
        $ce->{subtitle] = $title if defined( $title );
      }
      elsif( defined( $eventname ) )
      {
        $ce->{title} = norm( "$sport $eventname" );
        $ce->{subtitle} = $title if defined( $title );
      }
      elsif( defined( $title ) or defined( $subtitle ) )
      {
        $ce->{title} = norm( "$sport $title" );
      }
      else
      {
        error( "Expressen: $filename Empty title" );
      }

      extract_extra_info( $ce );

      $dsh->AddProgramme( $ce );
    }
    
    $dsh->EndBatch( 1, undef );
    
  }
 
  if( defined( $date ) )
  {
    $dsh->EndBatch( 1, log_to_string_result( $loghandle ) );
  }
  
}

sub extract_extra_info
{
  my( $ce ) = shift;

  return;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
