package NonameTV::XmltvValidate;

use strict;

use XML::LibXML;
use Date::Manip;
use Compress::Zlib;

=pod

Validate xmltv-files to see that:

Each file is valid xml.
Each file conforms to the xmltv-dtd.
Each programme has a valid channel identifier.
Each programme has a valid start and stop-time.
Each programme has a non-empty title.
Stop-time is strictly later than start-time for each programme.
No programmes overlap within a file.

The validation assumes that the input-file is already sorted by channel and
start-time.

=cut

my( $dtd, $parser );

sub slurp
{
  my( $file ) = @_;

  local(*INPUT, $/);
  open (INPUT, $file)     || die "can't open $file: $!";
  my $var = <INPUT>;
  
  return \$var;
}

BEGIN {
  use Exporter   ();
  our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
  
  @ISA         = qw(Exporter);
  @EXPORT      = qw( );
  %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
  @EXPORT_OK   = qw/xmltv_validate_file/;
  
  my $dtd_str = slurp( "/usr/share/sgml/xmltv/dtd/0.5/xmltv.dtd" );
  $dtd = XML::LibXML::Dtd->parse_string(${$dtd_str});

  $parser = XML::LibXML->new();
  $parser->line_numbers(1);

}
our @EXPORT_OK;

sub xmltv_validate_file
{
  my( $file, $outf ) = @_;
  my $errors = 0;

  if( not defined $outf )
  {
    $outf = sub { };
  }

  my $doc;

  if( $file =~ /\.gz$/ )
  {
    my $compressed_ref = slurp( $file );
    my $xmldata = Compress::Zlib::memGunzip( $compressed_ref );
    eval { $doc = $parser->parse_string( $xmldata ); };
  }
  else
  {
    eval { $doc = $parser->parse_file( $file ); };
  }

  if( $@ )
  {
    $outf->($file, 0, $@ );
    return 1;
  }

  eval { $doc->validate( $dtd ) };  
  if( $@ )
  {
    $outf->( $file, 0, $@ );
    return 1;
  }

  my $d = {};

  my $ns = $doc->find( "//programme" );
  
  my $lastchannel = "no such channel";

  my $laststop;
  my $laststop_d;

  foreach my $p ($ns->get_nodelist)
  {
    my $channel = $p->findvalue('@channel');
    my $start = $p->findvalue('@start');
    my $stop = $p->findvalue('@stop');
    my $title = $p->findvalue('title/text()');
    my $desc = $p->findvalue('desc/text()');

    if( $channel ne $lastchannel )
    {
      $laststop = "init";
      $laststop_d = ParseDate( "1970-01-01 00:00:00 +0000" );
      $lastchannel = $channel;
    }

    my $w = sub 
    { 
      $errors++;
      $outf->( $file, $p->line_number(), $_[0] );
    };

    $w->( "Illegal channel-id $channel" )
      if( $channel !~ /^[-a-z0-9]+(\.[-a-z0-9]+)+$/ );

    $w->( "Empty title" )    
      if( $title =~ /^\s*$/ );

#    $w->( "Empty description for $title" )    
#      if( $desc =~ /^\s*$/ );
    
    my $start_d = ParseDate( $start );

    if( !$start_d )
    {
      $w->( "Illegal start " . pt($start) );
      next;
    }

    my $stop_d = ParseDate( $stop );

    if( !$stop_d )
    {
      $w->( "Illegal stop " . pt($stop) );
      next;
    }

    if( Date_Cmp( $start_d, $stop_d ) >= 0 )
    {
      $w->( "Start isn't earlier than stop: " . pt($start) . " -> " . 
            pt($stop) );
      next;
    }

    if( Date_Cmp( $laststop_d, $start_d ) > 0 )
    {
      $w->( "Overlaps with previous programme " . pt($laststop) . " -> " .
            pt($start) );
    }

    $laststop = $stop;
    $laststop_d = $stop_d;
  }

  return $errors;
}

sub pt
{
  my( $dt ) = @_;

  $dt =~ s/^(\d{8})/$1 /;
  return $dt;
}
