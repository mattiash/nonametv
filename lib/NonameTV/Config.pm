package NonameTV::Config;

=head1 NAME

NonameTV::Config - Read and parse the configuration file(s) for
NonameTV.

=head1 SYNOPSIS

 use NonameTV::Config qw/ReadConfig/;

 my $conf = ReadConfig()

=head1 DESCRIPTION


=cut

use File::Slurp;

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
    
    # set the version for version checking
    $VERSION     = 0.3;

    @ISA         = qw(Exporter);
    @EXPORT      = qw( );
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
    @EXPORT_OK   = qw/ReadConfig/;
}
our @EXPORT_OK;

# Global variable containing the configuration after ReadConfig
# has been called.
my $Conf;

sub ReadConfig {
  return $Conf if defined $Conf;

  my $file;
  if (-e "$HOME/.nonametv.conf") {
  	$file = "$HOME/.nonametv.conf";
  } elsif (-e "/etc/nonametv.conf") {
  	$file = "/etc/nonametv.conf";
  } else {
  	die "No configuration file found in $HOME/.nonametv.conf or /etc/nonametv.conf"
  }
  
  my $config = read_file( $file );

  my $conf = eval( $config );
  die "Error in configuration file $file: $@" if $@;

  $Conf = $conf;
  return $conf;
}

1;
