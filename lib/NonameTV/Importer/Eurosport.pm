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

use NonameTV qw/MyGet Utf8Conv/;
use NonameTV::Log qw/get_logger start_output/;
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

  my $l = $self->{logger};
  my $dsh = $self->{datastorehelper};

  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_string($$cref); };
  if( $@ ne "" )
  {
    $l->error( "$batch_id: Failed to parse: $@" );
    return;
  }

  $dsh->StartBatch( $batch_id, $chd->{id} );

  my $ns = $doc->find( "//programme" );
  
  if( $ns->size() == 0 )
  {
    $l->error( "$batch_id: No programme entries found" );
    return;
  }

  my $currdate = "none";
  foreach my $p ($ns->get_nodelist)
  {
    my $sportname = $p->findvalue('sportname/text()');
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

    # Fix encoding error in source-file.
    $title =~ s/^'ventyr$/Äventyr/;

    # Fix strange title
    $title =~ s/_\._//;

    my $data = {
      title       => $title,
      description => norm( $description ),
      start_time  => $starttime,
      end_time    => $endtime,
    };
    
    $dsh->AddProgramme( $data );            
  }
  
  $dsh->EndBatch(1);
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

# Delete leading and trailing space from a string.
# Convert all whitespace to spaces. Convert multiple
# spaces to a single space.
# Remove all html-tags.
sub norm
{
    my( $instr ) = @_;

    return "" if not defined( $instr );

    my $str = Utf8Conv( $instr );

    $str =~ s/^\s+//;
    $str =~ s/\s+$//;

    $str =~ tr/\n\r\t /    /s;

    return $str;
}

1;
