package NonameTV;

use strict;
use warnings;

# Mark this source-file as encoded in utf-8.
use utf8;

use LWP::UserAgent;
use File::Temp qw/tempfile tempdir/;
use Unicode::String qw/utf8/;

use NonameTV::StringMatcher;
use NonameTV::Log qw/logdie/;

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
    
    # set the version for version checking
    $VERSION     = 0.3;

    @ISA         = qw(Exporter);
    @EXPORT      = qw( );
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
    @EXPORT_OK   = qw/MyGet expand_entities 
                      Html2Xml Htmlfile2Xml
                      Wordfile2HtmlTree Htmlfile2HtmlTree
                      Word2Xml Wordfile2Xml 
                      norm AddCategory
                      ParseDescCatSwe FixProgrammeData/;
}
our @EXPORT_OK;

my $wvhtml = '/usr/bin/wvHtml --charset=utf8';
# my $wvhtml = '/usr/bin/wvHtml';

# Global variable containing the configuration after ReadConfig
# has been called.
our $Conf;

sub ReadConfig
{
  my( $file ) = @_;

#  $file = "/etc/nonametv-utf8.conf" unless defined $file;
  $file = "/etc/nonametv.conf" unless defined $file;

  open IN, "< $file" or die "Failed to read from configuration file $file";
  my $config = "";
  while(<IN>)
  {
    $config .= $_;
  }

  my $conf = eval( $config );
  die "Error in configuration file $file: $@" if $@;

  NonameTV::Log::init( $conf );

  $Conf = $conf;
  return $conf;
}

my $ua = LWP::UserAgent->new( agent => "Grabber from http://tv.swedb.se", 
                              cookie_jar => {} );

# Fetch a url. Returns ($content, true) if data was fetched from server and
# different from the last time the same url was fetched, ($content, false) if
# it was fetched from the server and was the same as the last time it was
# fetched and (undef,$error_message) if there was an error fetching the data.
 
sub MyGet
{
  my( $url ) = @_;
  my $res = $ua->get( $url );
  
  if( $res->is_success )
  {
    return ($res->content, not defined( $res->header( 'X-Content-Unchanged' ) ) );
  }
  else
  {
    return (undef, $res->status_line );
  }
}

# åäö ÅÄÖ
my %ent = (
           257  => 'ä',
           337  => 'ö',
           8211 => '-',
           8212 => '--',
           8216 => "'",
           8217 => "'",
           8220 => '"',
           8221 => '"',
           8230 => '...',
           8364 => "(euro)",
           );

sub _expand
{
  my( $num, $str ) = @_;

  if( not defined( $ent{$num} ) )
  {
    $ent{$num} = "";
    print STDERR "Unknown entity $num in $str\n";
  }

  return $ent{$num};
}

sub expand_entities
{
  my( $str ) = @_;

  $str =~ s/\&#(\d+);/_expand($1,$str)/eg;

  return $str;
}

=item Html2Xml( $content )

Convert the HTML in $content into an XML::LibXML::Document.

Prints an error-message to STDERR and returns undef if the conversion
fails.

=cut

sub Html2Xml
{
  my $xml = XML::LibXML->new;
  $xml->recover(1);
  
  # Stupid XML::LibXML writes to STDERR. Redirect it temporarily.
  open(SAVERR, ">&STDERR"); # save the stderr fhandle
  print SAVERR "Nothing\n" if 0;
  open(STDERR,"> /dev/null");
  
  my $doc;
  eval { $doc = $xml->parse_html_string($_[0]); };
  
  # Restore STDERR
  open( STDERR, ">&SAVERR" );
  
  if( $@ ne "" )
  {
    print "parse_html_string failed: $@\n";
    return undef;
  }

  return $doc;
}

=item Htmlfile2Xml( $filename )

Convert the HTML in a file into an XML::LibXML::Document.

Prints an error-message to STDERR and returns undef if the conversion
fails.

=cut

sub Htmlfile2Xml
{
  my( $filename ) = @_;

  my $xml = XML::LibXML->new;
  $xml->recover(1);
  
  # Stupid XML::LibXML writes to STDERR. Redirect it temporarily.
  open(SAVERR, ">&STDERR"); # save the stderr fhandle
  print SAVERR "Nothing\n" if 0;
  open(STDERR,"> /dev/null");
  
  my $doc;
  eval { $doc = $xml->parse_html_file($filename); };
  
  # Restore STDERR
  open( STDERR, ">&SAVERR" );
  
  if( $@ ne "" )
  {
    print "Failed to parse $filename: $@\n";
    return undef;
  }

  return $doc;
}


=item Word2Xml( $content )

Convert the Microsoft Word document in $content into html and return
the html as an XML::LibXML::Document.

Prints an error-message to STDERR and returns undef if the conversion
fails.

=cut

sub Word2Xml
{
  my( $content ) = @_;
  
  my( $fh, $filename ) = tempfile();
  print $fh $content;
  close( $fh );

  my $doc = Wordfile2Xml( $filename );
  unlink( $filename );
  return $doc;
}

sub Wordfile2Xml
{
  my( $filename ) = @_;

  my $html = qx/$wvhtml "$filename" -/;
  if( $? )
  {
    print "$wvhtml $filename - failed: $?\n";
    return undef;
  }
  
  # Remove character that makes LibXML choke.
  $html =~ s/\&hellip;/.../g;
  
  return Html2Xml( $html );
}

# Remove any strange quotation marks and other syntactic marks
# that we don't want to have. Remove leading and trailing space as well
# multiple whitespace characters.
# Returns the empty string if called with an undef string.
sub norm
{
  my( $str ) = @_;

  return "" if not defined( $str );

# Uncomment the code below and change the regexp to learn which
# character code perl thinks a certain character has.
# These codes can be used in \x{YY} expressions as shown below.
#  if( $str =~ /unique string/ ) {
#    for( my $i=0; $i < length( $str ); $i++ ) {
#      printf( "%2x: %s\n", ord( substr( $str, $i, 1 ) ), 
#               substr( $str, $i, 1 ) ); 
#    }
#  }

  $str = expand_entities( $str );
  
  $str =~ tr/\x{96}\x{93}\x{94}/-""/; #
  $str =~ tr/\x{201d}\x{201c}/""/;
  $str =~ s/\x{85}/... /g;
  $str =~ s/\x{2026}/.../sg;

  $str =~ s/^\s+//;
  $str =~ s/\s+$//;
  $str =~ tr/\n\r\t /    /s;
  
  return $str;
}

# Generate HTML file in tempdir and run Htmlfile2HtmlTree
sub Wordfile2HtmlTree
{
  my ($filename) = @_;

  my $dir= tempdir( CLEANUP => 1 );
  (my $htmlfile= "$filename.html") =~ s|.*/([^/]+)$|$1|;
  if(system "$wvhtml --targetdir=\"$dir\" \"$filename\" \"$htmlfile\"") {
      print "$wvhtml --targetdir=\"$dir\" \"$filename\" \"$htmlfile\" failed: $?\n";
      return undef;
  }
  return &Htmlfile2HtmlTree("$dir/$htmlfile");
}

# Generate HTML::Tree from html file
sub Htmlfile2HtmlTree
{
    my ($filename)= @_;
    my $tree = HTML::TreeBuilder->new();
    open(my $fh, "<:utf8", "$filename") 
      or logdie( "Failed to read from $filename" );
    
    $tree->parse_file($fh); 

    return $tree;
}

=item AddCategory

Add program_type and category to an entry if the entry does not already
have a program_type and category. 

AddCategory( $ce, $program_type, $category );

=cut

sub AddCategory
{
  my( $ce, $program_type, $category ) = @_;

  if( not defined( $ce->{program_type} ) and defined( $program_type )
      and ( $program_type =~ /\S/ ) )
  {
    $ce->{program_type} = $program_type;
  }

  if( not defined( $ce->{category} ) and defined( $category ) 
      and ( $category =~ /\S/ ) )
  {
    $ce->{category} = $category;
  }
}

=item ParseDescCatSwe

Parse a program description in Swedish and return program_type
and category that can be deduced from the description.

  my( $pty, $cat ) = ParseDescCatSwe( "Amerikansk äventyrsserie" );

=cut

my $sm = NonameTV::StringMatcher->new();
$sm->AddRegexp( qr/kriminalserie/i,      [ 'series', 'Crime/Mystery' ] );
$sm->AddRegexp( qr/deckarserie/i,        [ 'series', 'Crime/Mystery' ] );
$sm->AddRegexp( qr/polisserie/i,         [ 'series', 'Crime/Mystery' ] );
$sm->AddRegexp( qr/familjeserie/i,       [ 'series', undef ] );
$sm->AddRegexp( qr/tecknad serie/i,      [ 'series', undef ] );
$sm->AddRegexp( qr/animerad serie/i,     [ 'series', undef ] );
$sm->AddRegexp( qr/dramakomediserie/i,   [ 'series', 'Comedy' ] );
$sm->AddRegexp( qr/dramaserie/i,         [ 'series', 'Drama' ] );
$sm->AddRegexp( qr/resedokumentärserie/i,[ 'series', 'Food/Travel' ] );
$sm->AddRegexp( qr/komediserie/i,        [ 'series', 'Comedy' ] );
$sm->AddRegexp( qr/realityserie/i,       [ 'series', 'Reality' ] );
$sm->AddRegexp( qr/realityshow/i,        [ 'series', 'Reality' ] );
$sm->AddRegexp( qr/dokusåpa/i,           [ 'series', 'Reality' ] );
$sm->AddRegexp( qr/actiondramaserie/i,   [ 'series', 'Action' ] );
$sm->AddRegexp( qr/actionserie/i,        [ 'series', 'Action' ] );
$sm->AddRegexp( qr/underhållningsserie/i,[ 'series', undef ] );
$sm->AddRegexp( qr/äventyrsserie/i,      [ 'series', 'Action/Adv' ] );
$sm->AddRegexp( qr/äventyrskomediserie/i,[ 'series', 'Comedy' ] );
$sm->AddRegexp( qr/dokumentärserie/i,    [ 'series', 'Documentary' ] );
$sm->AddRegexp( qr/dramadokumentär/i,    [ undef,    'Documentary' ] );

$sm->AddRegexp( qr/barnserie/i,          [ 'series', "Children's" ] );
$sm->AddRegexp( qr/matlagningsserie/i,   [ 'series', 'Cooking' ] );
$sm->AddRegexp( qr/motorserie/i,         [ 'series', undef ] );
$sm->AddRegexp( qr/fixarserie/i,         [ 'series', "Home/How-to" ] );
$sm->AddRegexp( qr/science[-\s]*fiction[-\s]*serie/i, 
                [ 'series', 'SciFi' ] );
$sm->AddRegexp( qr/barnprogram/i,          [ undef, "Children's" ] );

# Movies
$sm->AddRegexp( qr/\b(familje|drama)*komedi\b/i,  [ 'movie', "Comedy" ] );

$sm->AddRegexp( qr/\b(krigs|kriminal)*drama\b/i,  [ 'movie', "Drama" ] );

$sm->AddRegexp( qr/\baction(drama|film)*\b/i,     [ 'movie', "Action/Adv" ] );

$sm->AddRegexp( qr/\b.ventyrsdrama\b/i,           [ 'movie', "Action/Adv" ] );

$sm->AddRegexp( qr/\bv.stern(film)*\b/i,          [ 'movie', undef ] );

$sm->AddRegexp( qr/\b(drama)*thriller\b/i,        [ 'movie', "Crime" ] );

$sm->AddRegexp( qr/\bscience\s*fiction(rysare)*\b/i, [ 'movie', "SciFi" ] );

$sm->AddRegexp( qr/\b(l.ng)*film\b/i,             [ 'movie', undef ] );


sub ParseDescCatSwe
{
  my( $desc ) = @_;

  return (undef, undef) if not defined $desc;

  my $res = $sm->Match( $desc );
  if( defined( $res ) ) 
  {
    return @{$res};
  }
  else
  {
    return (undef,undef);
  }
}

sub FixProgrammeData
{
  my( $d ) = @_;

  $d->{title} =~ s/^s.songs+tart\s*:*\s*//gi;
  $d->{title} =~ s/^seriestart\s*:*\s*//gi;
  $d->{title} =~ s/^reprisstart\s*:*\s*//gi;
  $d->{title} =~ s/^programstart\s*:*\s*//gi;

  $d->{title} =~ s/^s.songs*avslutning\s*:*\s*//gi;
  $d->{title} =~ s/^sista\s+delen\s*:*\s*//gi;

  if( $d->{title} =~ s/^((matin.)|(fredagsbio))\s*:\s*//gi )
  {
    $d->{program_type} = 'movie';
    $d->{category} = 'Movies';
  }

  # Set program_type to series if the entry has an episode-number
  # but doesn't have a program_type.
  if( exists( $d->{episode} ) and defined( $d->{episode} ) and
      ( (not defined($d->{program_type})) or ($d->{program_type} =~ /^\s*$/) ) )
  {
    $d->{program_type} = "series";
  }
}
  
1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
