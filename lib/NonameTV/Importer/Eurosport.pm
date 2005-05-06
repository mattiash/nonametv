package NonameTV::Importer::Eurosport;

=pod

Eurosport currently delivers data as a single big file that we fetch from
their website. This is handled as a single batch by the importer.

The file is an xmlfile with content in entries:

<TVSchedule>
    <emi_id>2046716</emi_id>
    <start_date>2004-11-21T09:00:00.0000000+01:00</start_date>
    <end_date>2004-11-21T10:30:00.0000000+01:00</end_date>
    <duree>15</duree>
    <header>VM från Taiwan &lt;BR&gt;  1:a omgången: Taiwan - Egypten</header>

    <features>1:a omgången: Taiwan - Egypten</features>
    <description>&lt;P&gt;Den femte upplagan av VM i futsal spelas 21 november - 5 december på Taiwan. Eurosport sänder direkt från gruppspelet, semifinalerna samt finalen. De fyra tidigare VM-turneringarna har spelats i Nederländerna (1989), Hong Kong (1992), Spanien (1996) och Guatemala (2000). &lt;/P&gt;&lt;BR&gt;&lt;P&gt;Matcherna kommer att spelas på två arenor; Taiwan University Gymnasium i huvudstaden Taibei samt Linkou Gymnasium i Tao Yuan County. Spelformatet i VM är två gruppspel, med fyra grupper i det första och två i det andra. Därefter följer semifinaler och final. Följande lag spelar i den första gruppspelsomgången&lt;/P&gt;&lt;BR&gt;&lt;P&gt;Grupp A: Taiwan, Egypten, Spanien och Ukraina&lt;/P&gt;&lt;BR&gt;&lt;P&gt;Grupp B: Australien, Brasilien, Tjeckien och Thailand&lt;/P&gt;&lt;BR&gt;&lt;P&gt;Grupp C: Italien, USA, Japan och Paraguay&lt;/P&gt;&lt;BR&gt;&lt;P&gt;Grupp D: Iran, Portugal, Kuba och Argentina&lt;/P&gt;&lt;BR&gt;&lt;P&gt;Trefaldiga världsmästarna (1989, 1992 och 1996) Brasilien är favoriter tillsammans med regerande världsmästarna Spanien, som överraskande slog just brassarna i finalen vid VM 2000. &lt;/P&gt;&lt;BR&gt;&lt;P&gt;DK: Henrik Hvillum&lt;/P&gt;&lt;BR&gt;&lt;P&gt;SE: Mikael Bergvall&lt;/P&gt;</description>

    <sport_id>228</sport_id>
    <retrans_id>1</retrans_id>
    <retrans_name>DIREKT</retrans_name>
  </TVSchedule>

Note the embedded html-tags in the data-sections.

Eurosport have said that they will switch to another backend soon, so
this might change.

Features:

subtitles

=cut

use strict;
use warnings;

use DateTime;
use XML::LibXML;
use IO::Wrap;

use NonameTV qw/MyGet Utf8Conv/;
use NonameTV::Log qw/get_logger start_output/;

use NonameTV::Importer::BaseOne;

use base 'NonameTV::Importer::BaseOne';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);
    
    $self->{grabber_name} = "Eurosport";

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";
    return $self;
}

sub ImportContent
{
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $l = $self->{logger};
  my $ds = $self->{datastore};

  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_string($$cref); };
  if( $@ ne "" )
  {
    $l->error( "$batch_id: Failed to parse" );
  }

  $self->LoadSportId( $xml );

  $ds->StartBatch( $batch_id );
  
  my $ns = $doc->find( "//TVSchedule" );
  
  if( $ns->size() == 0 )
  {
    $l->error( "$batch_id: No programme entries found" );
    next;
  }
  
  foreach my $p ($ns->get_nodelist)
  {
    my $fulltitle = $p->findvalue('header/text()');
    my( $title, $subtitle ) = split( "<BR>", $fulltitle );
    
    my $start_date = $p->findvalue( 'start_date/text()' );
    my $end_date = $p->findvalue( 'end_date/text()' );
    
    my $description = $p->findvalue( 'description/text()' );
    my $sport_id = $p->findvalue( 'sport_id' );
    my $sport_name = $self->{sportidname}->{$sport_id};

    if( not defined( $sport_name ) )
    {
#      print "Unknown sport_id $sport_id\n";
    }

    if( defined( $sport_name ) and 
        ($sport_name eq "Nyheter" or $sport_name eq "Sport") )
    {
      $sport_name = undef;
    }

    my $start = create_dt( $start_date );
    my $end = create_dt( $end_date );
    
    if( DateTime->compare( $start, $end ) == 1 )
    {
      # The end-time has the wrong date when a program ends on a
      # different day than it started.
      $end = $end->add( days => 1 );
    }
    
    my $data = {
      channel_id  => $chd->{id},
      title       => defined( $sport_name ) ? norm("$sport_name: $title") : 
                     norm( $title ),
      description => norm($description),
      start_time  => $start->ymd("-") . " " . $start->hms(":"),
      end_time    => $end->ymd("-") . " " . $end->hms(":"),
    };
    
    $data->{subtitle} = norm($subtitle) 
      if defined $subtitle;
    
    $ds->AddProgramme( $data );            
  }
  
  $ds->EndBatch(1);
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my( $xmltvid, $date ) = ($batch_id =~ /(.+)_(.+)/);

  # NumOfWeeks doesn't work...
  my $url = $self->{UrlRoot} . '?LanguageCode=sv&NumOfWeeks=3';

  my( $content, $code ) = MyGet( $url );
  return( $content, $code );
}

sub LoadSportId
{
  my $self = shift;
  my( $xml ) = @_;

  return if( defined( $self->{sportidname} ) );

  my $l = $self->{logger};

  my( $content, $code ) = MyGet( $self->{SportIdUrl} );

  if( not defined $content )
  {
    $l->error( "Eurosport: Failed to fetch sport_id mappings" );
    exit 1;
  }

  # Some characters are encoded in CP1252 even though the 
  # header says iso-8859-1
  $content =~ tr/\x86\x84\x94/åäö/;

  my $doc;
  eval { $doc = $xml->parse_string($content); };
  if( $@ ne "" )
  {
    $l->error( "Eurosport: Failed to parse sport_id mappings" );
    exit 1;
  }
  
  my %id;
  my $ns = $doc->find( '//SPTR[@LAN_ID="7"]' );
  
  if( $ns->size() == 0 )
  {
    $l->error( "Eurosport: No sport_id mappings found" );
    exit 1;
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
}

sub create_dt
{
  my( $date ) = @_;
  
  my( $year, $month, $day, $hour, $minute, $second, $tz ) = 
    ($date =~ /(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)\.\d+(.\d+)/);
  
  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          second => $second,
                          time_zone => "${tz}00",
                          );
  
  $dt->set_time_zone( 'UTC' );

  return $dt;
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

    # Replace embedded html tags with space.
    $str =~ s/\<.*?\>/ /g;

    $str =~ s/^\s+//;
    $str =~ s/\s+$//;

    $str =~ tr/\n\r\t /    /s;

    return $str;
}

1;
