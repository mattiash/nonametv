package NonameTV::Importer::Axess;

use strict;
use warnings;

=pod

Importer for files in the format provided by Axess Television.
This is supposedly the format defined by TTSpektra. 

=cut

use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV qw/ParseXml norm/;

use DateTime;
use Encode;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);


    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";
    defined( $self->{LoginUrl} ) or die "You must specify LoginUrl";

    $self->{datastore}->{SILENCE_END_START_OVERLAP} = 1;
    return $self;
}

sub InitiateDownload {
  my $self = shift;

  # Do the login. This will set a cookie that will be transferred on all
  # subsequent page-requests.
  my( $dataref, $error ) = $self->{cc}->GetUrl( $self->{LoginUrl} );
  
  return $error;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $date ) = ( $objectname =~ /_(.*)$/ );
 
  my $url = $self->{UrlRoot} . $date;

  # Only one url to look at and no error
  return ([$url], undef);
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  if( $$cref eq "" ) {
    return (undef, "No data found." );
  }

  my $doc = ParseXml( $cref );
  
  if( not defined $doc ) {
    return (undef, "ParseXml failed" );
  } 

  my $xp = XML::LibXML::XPathContext->new($doc);
  
  # Create namespace
  # http://perl-xml.sourceforge.net/faq/#namespaces_xpath
  $xp->registerNs(tt => 'http://www.ttspektra.se' );
  
  # Remove all OtherBroadcast since they change
  # each time the data for today is downloaded.
  my $ns = $xp->find( "//tt:OtherBroadcast" );

  foreach my $n ($ns->get_nodelist) {
    $n->unbindNode();
  }

  my $str = encode( "utf-8", $doc->toString( 1 ) );

  return( \$str, undef );
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContent {
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};

  my $doc = ParseXml( $cref );
  my $xp = XML::LibXML::XPathContext->new($doc);
  
  # Create namespace
  # http://perl-xml.sourceforge.net/faq/#namespaces_xpath
  $xp->registerNs(tt => 'http://www.ttspektra.se' );
  
  my $ns = $xp->find( "//tt:TVRProgramBroadcast" );

  if( $ns->size() == 0 ) {
    error( "$batch_id: No data found" );
    return 0;
  }
  
  foreach my $pb ($ns->get_nodelist)
  {
    my $start = $xp->findvalue( 
      'tt:TVRBroadcast/tt:BroadcastDateTime/tt:StartDateTime', $pb );
    my $end = $xp->findvalue( 
      'tt:TVRBroadcast/tt:BroadcastDateTime/tt:EndDateTime', $pb );
    my $url = $xp->findvalue( 
      'tt:TVRBroadcast/tt:BroadcastInformation/tt:WebPage/@URL', $pb );
    my $title = norm( $xp->findvalue( 'tt:TVRProgram/tt:Title', $pb ) );
    my $subtitle = norm( 
      $xp->findvalue( 'tt:TVRProgram/tt:EpisodeTitle', $pb ) );

    if( $title eq $subtitle ) {
      my( $title2, $subtitle2 ) = ( $title =~ /(.*?) - (.*)/ );
      if( defined( $subtitle2 ) ) {
        $title = $title2;
        $subtitle = $subtitle2;
      }
      else {
        $subtitle = "";
      }
    }

    my $intro = $xp->findvalue( 'tt:TVRProgram/tt:Intro', $pb );
    my $description = $xp->findvalue( 
      'tt:TVRProgram/tt:Description/tt:TextDesc', $pb );
    my $episodenum = $xp->findvalue( 'tt:TVRProgram/tt:EpisodeNumber', $pb );

    my $ce = {
      channel_id  => $chd->{id},
      start_time  => ParseDateTime( $start ),
      end_time    => ParseDateTime( $end ),
      title       => norm( $title ),
      description => norm( "$intro $description" ),
      url         => $url,
    };

    if( $subtitle ne "" ) {
      $ce->{subtitle} = norm( $subtitle );
    }

    if( $episodenum ne "" ) {
      $ce->{episode} = " . " . ($episodenum-1) . " . ";
    }

    $ds->AddProgramme( $ce );
  }

  return 1;
}

sub ParseDateTime {
  my( $str ) = @_;

  my( $year, $month, $day, $hour, $minute, $second ) = ($str =~ /
    ^(\d{4})-(\d{2})-(\d{2})T
     (\d{2}):(\d{2}):(\d{2})$/x );

  my $dt;
  eval {
    $dt = DateTime->new(
    year => $year,
    month => $month,
    day => $day,
    hour => $hour,
    minute => $minute,
    time_zone => 'local' );
  };

  error( "$@" ) if $@;

  return undef if not defined $dt;
  
  if( $second > 0 ) {
    $dt->add( minutes => 1 );
  }
  
  $dt->set_time_zone( 'UTC' );
  
  return $dt->ymd() . " " . $dt->hms();
}

1;
