package NonameTV::FileStore;

use strict;

use NonameTV::Log qw/d p w f/;

use File::Slurp qw/read_file/;
use LWP::Simple qw/get/;
use Digest::MD5 qw/md5_hex/;
use File::Path qw/mkpath/;

use Carp qw/croak carp/;

use utf8;

=begin nd

Class: NonameTV::FileStore

=cut

=begin nd:

Constructor: new

=cut 

sub new #( $param )
{
  my $class = ref( $_[0] ) || $_[0];

  my $self = {};
  bless $self, $class;

  # Copy the parameters supplied in the constructor.
  foreach my $key ( keys( %{ $_[1] } ) ) {
    $self->{$key} = ( $_[1] )->{$key};
  }

  croak "Failed to specify Path"
      if not defined $self->{Path};

  $self->{_fl} = {};

  return $self;
}

=begin nd

Method: AddFile

Add a new file to the filestore for a specific channel. If an
identical file already exists (same filename and md5sum), no action is
performed. If a file with the same name but different content exists,
the old file is replaced with the new file.

Returns: undef

=cut

sub AddFile #( $xmltvid, $filename, $cref )
{
  my $self = shift;
  my( $xmltvid, $filename, $cref ) = @_;

  $self->LoadFileList( $xmltvid );

  carp "Cannot add a file to a remote filestore"
      if not $self->PathIsLocal();

  my $dir = $self->{Path} . "/$xmltvid";

  mkpath( $dir );

  my( $oldmd5, $ts ) = $self->GetFileMeta( $xmltvid, $filename );

  my $newmd5 = md5_hex( $$cref );
  if( not defined( $oldmd5 ) or ($oldmd5 ne $newmd5 ) ) {
    print "$oldmd5 - $newmd5\n";
    my $fullname = "$dir/$filename";
    open( OUT, "> $fullname" ) or die "Failed to write to $fullname";
    print OUT $$cref;
    close( OUT );
    
    $self->AddFileMeta( $xmltvid, $filename, $newmd5 );
  }
  else {
    print "Duplicate file skipped.\n";
  }
}

sub AddFileMeta {
  my $self = shift;
  my( $xmltvid, $filename, $md5 ) = @_;

  # Delete any entry with the same filename
  $self->{_fl}->{$xmltvid} = 
      [ grep { $_->[0] ne $filename } @{$self->{_fl}->{$xmltvid}} ];

  push @{$self->{_fl}->{$xmltvid}}, [ $filename, $md5, time()];
}

=begin nd

Method: ListFiles

Returns an array with arrayrefs, where each arrayref contains a
filename, an md5sum, and a timestamp for when the file was first added.

=cut

sub ListFiles #( $xmltvid )
{
  my $self = shift;
  my( $xmltvid ) = @_;

}

=begin nd

Method: GetFile

Returns a reference to the contents of the specified file.

=cut

sub GetFile {
  my $self = shift;
  my( $xmltvid, $filename ) = @_;

  my $fullname = $self->{Path} . "/$xmltvid/$filename";

  if( $self->PathIsLocal() ) {
    return read_file( $fullname, err_mode => 'quiet' );
  }
  else {
    return get( $fullname );
  }
}

sub GetFileMeta {
  my $self = shift;
  my( $xmltvid, $filename ) = @_;

  foreach my $e (@{$self->{_fl}->{$xmltvid}}) {
    return ($e->[1], $e->[2]) if $e->[0] eq $filename;
  }
  
  return undef;
}

=begin nd

Method: RemoveOldFiles

Remove all files for a specific channel that were added more than
$days days ago.

=cut

sub RemoveOldFiles #( $xmltvid, $days )
{
}

sub PathIsLocal {
  my $self = shift;

  return not $self->{Path} =~ /^http:/;
}

sub LoadFileList {
  my $self = shift;
  my( $xmltvid ) = @_;

  return if defined $self->{_fl}->{$xmltvid};

  my @d;

  my $fl = $self->GetFile( $xmltvid, "00files" );

  foreach my $line (split( "\n", $fl)) {
    my( $filename, $md5sum, $ts ) = split( "\t", $line );
    push @d, [ $filename, $md5sum, $ts ];
  }

  $self->{_fl}->{$xmltvid} = \@d;
  $self->{_flmodified}->{$xmltvid} = 0;
}

sub DESTROY {
  my $self = shift;

  foreach my $xmltvid (keys %{$self->{_fl}} ) {
    my $fullname = $self->{Path} . "/$xmltvid/00files";
    open( OUT, "> $fullname" ) or die "Failed to write to $fullname";
    foreach my $e (@{$self->{_fl}->{$xmltvid}}) {
      print OUT join( "\t", @{$e} ) . "\n";
    }
    close( OUT );
  }
}

=head1 COPYRIGHT

Copyright (C) 2008 Mattias Holmlund.

=cut

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
