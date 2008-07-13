package NonameTV::Factory;

use strict;

=head1 NAME

NonameTV::Factory

=head1 DESCRIPTION

Create other NonameTV objects based on the available configuration.

=head1 METHODS

=over 4

=cut

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
    
    @ISA         = qw(Exporter);
    @EXPORT      = qw( );
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
    @EXPORT_OK   = qw/ CreateDataStore CreateDataStoreDummy
                       CreateImporter CreateExporter
                       InitLog InitHttpCache
                     /;
}
our @EXPORT_OK;

use NonameTV::Config qw/ReadConfig/;

=item CreateImporter( $name, $ds )

Create an importer from the configuration in $conf->{Importer}->{$name}
and associate it with the NonameTV::DataStore in $ds.

Returns the newly created importer or dies if creation fails.

=cut

sub CreateImporter {
  my( $name, $ds ) = @_;

  my $conf = ReadConfig();
  
  if( not exists( $conf->{Importers}->{$name} ) ) {
    print STDERR "No such importer $name\n";
    exit 1;
  }

  my $imp_data = $conf->{Importers}->{$name};
  my $imp_type = $imp_data->{Type};

  if( not defined $imp_type ) {
    print STDERR "Importer $name has no Type-field\n";
    exit 1;
  }

  my $imp = eval "use NonameTV::Importer::$imp_type; 
                  NonameTV::Importer::${imp_type}->new( \$imp_data, \$ds );"
                      or die $@;
  return $imp;
}

=item CreateExporter( $name, $ds )

Create an exporter from the configuration in $conf->{Exporter}->{$name}
and associate it with the NonameTV::DataStore in $ds.

Returns the newly created exporter or dies if creation fails.

=cut

sub CreateExporter {
  my( $name, $ds ) = @_;

  my $conf = ReadConfig();
  
  if( not exists( $conf->{Exporters}->{$name} ) ) {
    print STDERR "No such exporter $name\n";
    exit 1;
  }

  my $exp_data = $conf->{Exporters}->{$name};
  my $exp_type = $exp_data->{Type};

  my $exp = eval "use NonameTV::Exporter::$exp_type; 
                  NonameTV::Exporter::${exp_type}->new( \$exp_data, \$ds );"
                      or die $@;
  return $exp;
}

=item CreateDataStore

Create a NonameTV::DataStore from the configuration.

Returns the newly created datastore or dies if creation fails.

=cut

sub CreateDataStore {
  my $conf = ReadConfig();
  
  require NonameTV::DataStore;
  return NonameTV::DataStore->new( $conf->{DataStore} );
}

=item CreateDataStoreDummy

Create a dummy datastore (see NonameTV::DataStore::Dummy) from the
configuration.

Returns the newly created datastore or dies if creation fails.

=cut

sub CreateDataStoreDummy {
  my $conf = ReadConfig();
  
  require NonameTV::DataStore::Dummy;
  return NonameTV::DataStore::Dummy->new( $conf->{DataStore} );;
}

=item InitLog

Initialize the NonameTV::Log module from the configuration.

=cut

sub InitLog {
  require NonameTV::Log;
  my $conf = ReadConfig();
  NonameTV::Log::init( $conf );
}

=item InitLog

Initialize the HTTP::Cache::Transparent module from the configuration.

=cut

sub InitHttpCache {
  require HTTP::Cache::Transparent;
  my $conf = ReadConfig();
  HTTP::Cache::Transparent::init( $conf->{Cache} );
}

1;

