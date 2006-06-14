package NonameTV::Importer::Eurosport;

=pod

Eurosport currently delivers data as a single big file per channel that 
we fetch from their website. This is handled as a single batch by the 
importer.

The file is an xmlfile with content in entries:

<programme>
  <emi_id>2341753</emi_id>
  <sportid>14</sportid>
  <langueid>7</langueid>
  <comp_id>31</comp_id>
  <evt_id>939</evt_id>
  <cat_id>82</cat_id>
  <leg_id>948</leg_id>
  <snc_id>16616</snc_id>
  <sportname>Kanot</sportname>
  <emidate>2005-06-26</emidate>
  <startdate>14:00:00</startdate>
  <enddate>15:30:00</enddate>
  <duree>01:30:00</duree>
  <description>EM i kanotslalom från Tacen, Slovenien
  </description>
  <retransid>1</retransid>
  <retransname>DIREKT</retransname>
  <features>
  </features>
  <desjournaliste>EM i kanotslalom från Tacen, Slovenien
  </desjournaliste>
</programme>

=cut

use strict;
use warnings;

use DateTime;
use XML::LibXML;
use IO::Wrap;

use NonameTV qw/MyGet norm/;
use NonameTV::Log qw/info progress error logdie/;
use NonameTV::DataStore::Helper;

use NonameTV::Importer::BaseOne;

use base 'NonameTV::Importer::BaseOne';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);
    
    $self->{grabber_name} = "Eurosport";

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $self->{datastorehelper} = $dsh;

    return $self;
}

sub ImportContent
{
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $dsh = $self->{datastorehelper};

  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_string($$cref); };
  if( $@ ne "" )
  {
    error( "$batch_id: Failed to parse: $@" );
    return 0;
  }

  $self->LoadSportId( $xml )
    or return 0;

  my $ns = $doc->find( "//programme" );
  
  if( $ns->size() == 0 )
  {
    error( "$batch_id: No programme entries found" );
    return 0;
  }

  my $currdate = "none";
  foreach my $p ($ns->get_nodelist)
  {
    my $sportid = $p->findvalue( 'sportid' );
    my $sportname = $self->{sportidname}->{$sportid};

    if( not defined( $sportname ) )
    {
      print "Unknown sportid $sportid\n";
      $sportname = $p->findvalue( 'sportname' );

      $sportname = ucfirst( lc( $sportname ) );
    }

    my $emidate = $p->findvalue('emidate/text()');

    my $starttime = $p->findvalue( 'startdate/text()' );
    my $endtime = $p->findvalue( 'enddate/text()' );
    
    my $description = $p->findvalue( 'description/text()' );

    if( $currdate ne $emidate )
    {
      $dsh->StartDate( $emidate );
      $currdate = $emidate;
    }

    my $title = norm( $sportname );

    my $data = {
      title       => $title,
      description => norm( $description ),
      start_time  => $starttime,
      end_time    => $endtime,
    };
    
    $dsh->AddProgramme( $data );            
  }
  
  # Success
  return 1;
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  # All data for a channel is supplied in a single file
  # with a static url.
  my $url = $self->{UrlRoot} . $data->{grabber_info};

  my( $content, $code ) = MyGet( $url );
  return( $content, $code );
}

sub LoadSportId
{
  my $self = shift;
  my( $xml ) = @_;

  return 1 if( defined( $self->{sportidname} ) );

  my( $content, $code ) = MyGet( $self->{SportIdUrl} );

  if( not defined $content )
  {
    error( "Eurosport: Failed to fetch sport_id mappings" );
    return 0;
  }

  # Some characters are encoded in CP1252 even though the 
  # header says iso-8859-1
  $content =~ tr/\x86\x84\x94/åäö/;

  my $doc;
  eval { $doc = $xml->parse_string($content); };
  if( $@ ne "" )
  {
    error( "Eurosport: Failed to parse sport_id mappings" );
    return 0;
  }
  
  my %id;
  my $ns = $doc->find( '//SPTR[@LAN_ID="7"]' );
  
  if( $ns->size() == 0 )
  {
    error( "Eurosport: No sport_id mappings found" );
    return 0;
  }
  
  foreach my $p ($ns->get_nodelist)
  {
    my $short_name = norm( $p->findvalue('@SPTR_SHORTNAME') );
    my $sport_id = norm( $p->findvalue( '@SPO_ID' ) );

    # TODO: This does not work correctly for changing the case of åäö.
    # Luckily, all åäö's are already the correct case.
    $id{$sport_id} = ucfirst(lc($short_name));
  }

  $self->{sportidname} = \%id;
  return 1;
}

1;
