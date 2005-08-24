package NonameTV::Importer::BaseOne;

use strict;
use warnings;

=pod

Abstract base-class for an Importer that downloads data in one 
file per channel. 

=cut

use DateTime;
use POSIX qw/floor/;

use NonameTV::Log qw/info progress error logdie/;

use NonameTV::Importer;

use base 'NonameTV::Importer';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{OptionSpec} = [ qw/force-update verbose short-grab/ ];
    $self->{OptionDefaults} = { 
      'force-update' => 0,
      'verbose'      => 0,
      'short-grab'   => 0,
    };

    return $self;
}

sub Import
{
  my $self = shift;
  my( $p ) = @_;
  
  NonameTV::Log::verbose( $p->{verbose} );

  my $ds = $self->{datastore};

  my $sth = $ds->Iterate( 'channels', { grabber => $self->{grabber_name} } )
      or logdie( "$self->{grabber_name}: Failed to fetch grabber data" );

  while( my $data = $sth->fetchrow_hashref )
  {
    if( $p->{'force-update'} )
    {
      # Delete all data for this channel.
      my $deleted = $ds->Delete( 'programs', { channel_id => $data->{id} } );
      progress( "Deleted $deleted records for $data->{xmltvid}" );
    }

    my $batch_id = $data->{xmltvid};

    $self->ImportBatch( $batch_id, $data, $p->{'force-update'} );
  }

  $sth->finish();
}

sub ImportContent
{
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  die "You must override ImportContent";
}

1;
