package NonameTV;

use strict;
use warnings;

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
    
    # set the version for version checking
    $VERSION     = 0.3;

    @ISA         = qw(Exporter);
    @EXPORT      = qw( );
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
    @EXPORT_OK   = qw//;
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

1;

  
