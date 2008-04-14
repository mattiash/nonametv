package NonameTV::Path;

=head1 NAME

NonameTV::Path - Locate different parts of the NonameTV source.

=head1 SYNOPSIS

 use NonameTV::Path;

 print NonameTV::Path::Root();

=head1 DESCRIPTION

Locates the full path to the directory where NonameTV is located.
This is done based on the location of the script that is running,
which means that it will work even if there are several instances
of NonameTV on your system.

To override the location, set the environment variable NONAMETV_ROOT so
that $NONAMETV_ROOT/lib/NonameTV/Path.pm exists.

=cut

use FindBin;
use Cwd qw/abs_path/;

my $root;

BEGIN {
  if( defined( $ENV{NONAMETV_ROOT} ) ) {
    $root = $ENV{NONAMETV_ROOT};
    if( not -f "$root/lib/NonameTV/Path.pm" ) {
      print STDERR "Failed to find NonameTV installation at $root.\n";
      print STDERR "Please set the NONAMETV_ROOT environment variable correctly.\n";
      exit 1;
    }
  }
  else {
    $root = abs_path( $FindBin::Bin );

    while( not -f "$root/lib/NonameTV/Path.pm" ) {
      my $oldroot = $root;
      $root = abs_path( "$root/.." );
      if( $root eq $oldroot ) {
	print STDERR "NonameTV::Path Failed to find the NonameTV installation directory.\n";
	print STDERR "Started at $FindBin::Bin/..\n";
	exit 1;
      }
    }
  }
}

sub Root {
  return $root;
}

sub Templates {
  return "$root/templates";
}

1;
