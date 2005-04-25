package NonameTV::Importer;

use strict;

use File::Copy;

=head1 NAME

NonameTV::Importer

=head1 DESCRIPTION

Abstract base-class for the NonameTV::Importer::* classes.

A package derived from NonameTV::Importer can be used to import
data from different datasources into the NonameTV programming
database.

NonameTV::Importer::*-objects are instantiated from the nonametv.conf
configuration file. To instantiate an object, add an entry
in the 'importers'-hash. Each entry consists of a hash with 
the package-name of the importer in the type-key and any other
parameters to the object in other keys.

=head1 METHODS

=over 4

=cut

=item new

The constructor for the object. Called with a hashref as the first parameter.
This is a ref to the configuration for the object from the nonametv.conf-
file. The second parameter is a NonameTV::DataStore object.

=cut

sub new
{
  my $class = ref( $_[0] ) || $_[0];

  my $self = { }; 
  bless $self, $class;

  # Copy the parameters supplied in the constructor.
  foreach my $key (keys(%{$_[1]}))
  {
      $self->{$key} = ($_[1])->{$key};
  }

  $self->{datastore} = $_[2];

  return $self;
}

=item Import

Import is called from the nonametv-import executable. It takes a hashref as 
the only parameter. The hashref 
points to a hash with the command-line parameters decoded by Getopt::Long 
using the $NonameTV::Importer::*::Options arrayref as format specification.

=cut

sub Import
{
  my( $self, $param ) = @_;
  
  die "You must override Import in your own class"
}

=item ImportFile

Import the content from a single file.

=cut

sub ImportFile
{
  my $self = shift;
  my( $contentname, $filename, $p ) = @_;

  my $content;

  # Load data from file
  {
    local( $/ ) ;
    open( my $fh, "$filename" ) 
        or die "Failed to read from $filename: $@";
    $content = <$fh>;
  }

  return $self->ImportContent( $contentname, \$content, $p );
}

=item ImportContent

Import the content from a string reference.

=cut

sub ImportContent
{
  my $self = shift @ARGV;
  my( $contentname, $filename, $p ) = @_;

  die "You must override ImportContent in your own class";
}

sub FetchData
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my $root = "/var/local/nonametv/override";
  my $code = 0;
  my $content;

  if( -f( "$root/new/$batch_id" ) )
  {
    move( "$root/new/$batch_id", "$root/data/$batch_id" );
    $code = 1;
  }

  if( -f( "$root/data/$batch_id" ) )
  {
    # Check if the data on site has changed
    my( $site_content, $site_code ) = 
      $self->FetchDataFromSite( $batch_id, $data );

    print STDERR "$batch_id New data available for override.\n"
      if( $site_code );
    
    $site_content = undef;

    # Load data from file
    {
      local( $/ ) ;
      open( my $fh, "$root/data/$batch_id" ) 
        or die "Failed to read form $root/data/$batch_id: $@";
      $content = <$fh>;
    }
  }
  else
  {
    ( $content, $code ) = $self->FetchDataFromSite( $batch_id, $data );
    if( -f( "$root/delete/$batch_id" ) )
    {
      # Delete the old override and force update from site.
      unlink( "$root/delete/$batch_id" );
      $code = 1;
    }
  }
  
  return ($content, $code);
}



=head1 CLASS VARIABLES

=item $OptionSpec, $OptionDefaults

Format specifications and default values for Getopt::Long.

our $OptionSpec = [ qw/force-update/ ];
our %OptionDefaults = ( 
                        'force-update' => 0,
                        );

 
=head1 COPYRIGHT

Copyright (C) 2004 Mattias Holmlund.

=cut

1;
