package NonameTV;

use strict;
use warnings;

use LWP::UserAgent;

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
    
    # set the version for version checking
    $VERSION     = 0.3;

    @ISA         = qw(Exporter);
    @EXPORT      = qw( );
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
    @EXPORT_OK   = qw/MyGet/;
}
our @EXPORT_OK;

sub ReadConfig
{
  my( $file ) = @_;

  $file = "/etc/nonametv.conf" unless defined $file;

  open IN, "< $file" or die "Failed to read from configuration file $file";
  my $config = "";
  while(<IN>)
  {
    $config .= $_;
  }

  my $conf = eval( $config );
  die "Error in configuration file $file: $@" if $@;
  return $conf;
}

my $ua = LWP::UserAgent->new( agent => "nonametv" );

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

1;

  
