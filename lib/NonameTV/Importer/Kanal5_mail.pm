package NonameTV::Importer::Kanal5_mail;

use strict;
use warnings;

use utf8;

use DateTime;
use XML::LibXML;
use File::Slurp;

use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::Kanal5_util qw/ParseData/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  $self->{grabber_name} = "Kanal5_mail";

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile
{
  my $self = shift;
  my( $filename, $chd ) = @_;

  progress( "Kanal5_mail: Processing $filename" );
  
  $self->{fileerror} = 0;

  my $dsh = $self->{datastorehelper};

  # We have no category information for data delivered via e-mail.
  my $cat = {};

  my $data = read_file( $filename );

  return ParseData( $filename, \$data, $chd, $cat, $dsh, 1 );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
