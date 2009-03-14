package NonameTV::Importer::NonstopWeb;

=pod

This importer imports data from Nonstop TVs public website.The data is
fetched as one html-file per day and channel.

=cut

use strict;
use warnings;

use DateTime;
use XML::LibXML;
use Encode qw/decode/;

use NonameTV qw/norm Html2Xml ParseXml/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $self->{datastorehelper} = $dsh;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $month, $day ) = ($objectname =~ /_(\d\d\d\d)-(\d\d)-(\d\d)/);


  my $dt = DateTime->new( year => $year,
			  month => $month,
			  day => $day );

  my $url = $dt->strftime( $chd->{grabber_info} );

  # Use DateTime->strftime to build url.
  return( $url, undef );
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  my $doc = Html2Xml( decode( "utf-8", $$cref ) );

  if( not defined $doc ) {
    return (undef, "Html2Xml failed" );
  } 

  my $outdoc = XML::LibXML::Document->new("1.0", "utf-8" );

  my $ns = $doc->find( '//ul[@id="schedule_list"]' );

  if( $ns->size() != 1 ) {
    return (undef, "Expected one schedule_list, got " . $ns->size() );
  }

  my $node = $ns->get_node(1);

  $outdoc->setDocumentElement( $node );

  my $str = $outdoc->toString(1);

  return( \$str, undef );
}

sub ContentExtension {
  return 'html';
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  my( $date ) = ($batch_id =~ /_(.*)$/);

  my $doc = ParseXml( $cref );

  if( not defined( $doc ) ) {
    error( "$batch_id: Failed to parse." );
    return 0;
  }
  
  my $ns = $doc->find( '/ul/li' );
  if( $ns->size() == 0 ) {
    error( "$batch_id: No data found" );
    return 0;
  }
  
  $dsh->StartDate( $date, "00:00" );
  
  foreach my $pgm ($ns->get_nodelist) {
    # The data consists of alternating rows with time+title or description.
    my $time = norm( $pgm->findvalue( './/span[@class="airtime"]//text()' ) );

    my $title = $pgm->findvalue( './/h2//text()' );
    my $desc  = $pgm->findvalue( './/p//text()' );

    my $ce =  {
      start_time  => $time,
      title       => norm($title),
      description => norm($desc),
    };
    
    extract_extra_info( $ce );
    $dsh->AddProgramme( $ce );
  }
  
  return 1;
}

sub extract_extra_info {
  my( $ce ) = shift;
}

1;
