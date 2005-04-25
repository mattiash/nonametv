package NonameTV::Importer::BaseOne;

use strict;
use warnings;

=pod

Abstract base-class for an Importer that downloads data in one 
file per channel. 

=cut

use DateTime;
use POSIX qw/floor/;

use NonameTV::Log qw/get_logger start_output/;

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

    $self->{logger} = get_logger(ref($self));
    return $self;
}

sub Import
{
  my $self = shift;
  my( $p ) = @_;
  
  my $l=$self->{logger};
  start_output( ref($self), $p->{verbose} );

  my $ds = $self->{datastore};

  my $sth = $ds->Iterate( 'channels', { grabber => $self->{grabber_name} } )
      or $l->logdie( "$self->{grabber_name}: Failed to fetch grabber data" );

  while( my $data = $sth->fetchrow_hashref )
  {
    if( $p->{'force-update'} )
    {
      # Delete all data for this channel.
      my $deleted = $ds->Delete( 'programs', { channel_id => $data->{id} } );
      $l->warn( "Deleted $deleted records for $data->{xmltvid}" );
    }

    my $batch_id = $data->{xmltvid};

    $l->info( "$batch_id: Fetching data" );
    
    my( $content, $code ) = $self->FetchData( $batch_id, $data );
    
    if ( defined( $content ) and
         ($p->{'force-update'} or ($code) ) )
    {
      $l->warn( "$batch_id: Processing data" );
      $self->ImportContent( $batch_id, \$content, $data );
    }
    elsif( not defined( $content ) )
    {
      $l->error( "$batch_id: Failed to fetch data" );
    }
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
