package NonameTV::Importer::BaseUnstructured;

use strict;
use warnings;

=pod

Abstract base-class for an Importer that uses data found in one directory
per channel where new files "magically appear" in the directory and must be
processed in the order that they appear.

=cut

use DateTime;
use POSIX qw/floor/;
use Encode;

use NonameTV::Log qw/d p w f StartLogSection EndLogSection/;

use NonameTV::Config qw/ReadConfig/;

use NonameTV::Importer;

use base 'NonameTV::Importer';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{OptionSpec} = [ qw/force-update verbose+ quiet+ rescan/ ];
    $self->{OptionDefaults} = { 
      'force-update' => 0,
      'verbose'      => 0,
      'quiet'        => 0,
      'rescan'         => 0,
    };

    my $conf = ReadConfig();
    
    $self->{filestore} = NonameTV::FileStore->new( 
       { Path => $conf->{FileStore} } );

    return $self;
}

sub ImportData {
  my $self = shift;
  my( $p ) = @_;
  
  NonameTV::Log::SetVerbosity( $p->{verbose}, $p->{quiet} );

  my $ds = $self->{datastore};
  my $fs = $self->{filestore};

  foreach my $data (@{$self->ListChannels()}) {
    p "Checking files";
    
    if( $p->{'rescan'} ) {
      $fs->RecreateIndex( $data->{xmltvid} );
    }
    
    my @processfiles;

    if( $p->{'force-update'} ) {
      # Delete all data for this channel.
      my $deleted = $ds->ClearChannel( $data->{id} );
      p "Deleted $deleted records";

      @processfiles = $fs->ListFiles( $data->{xmltvid} );
    }
    else {
      my @dbfiles = $ds->sa->LookupMany( "files", 
					 { channelid => $data->{id} } );
      my @old = map { [ $_->{filename}, $_->{md5sum} ] } @dbfiles;

      my @new = $fs->ListFiles( $data->{xmltvid} );

      CompareArrays( \@new, \@old, {
	added => sub { push @processfiles, $_ },
	deleted => sub {
	  $ds->sa->Delete( "files", { channelid => $data->{id},
				      filename => $_[0] } );
	},
	equal => sub { push( @processfiles, $_[0] ) 
			   if( $_[0]->[1] eq $_[1]->[1] );
		     },
	cmp => sub { $_[0]->[0] cmp $_[1]->[0] },
	max => [ "zzzzzzzz" ],
      } );
      
      # Process the oldest (lowest timestamp) files first.
      @processfiles = sort { $a->[2] <=> $b->[2] };
    }

    foreach my $f (@processfiles) {
      $ds->sa->Delete( "files", { channelid => $data->{id},
                                  filename => $file->[0] } );
      
      $ds->sa->Add( "files", { channelid => $data->{id},
                               filename => $file->[0],
                               'md5sum' => $file->[1],
                    } );

      $self->DoImportContentFile( $file->[0], $data );
    }
  }
}

sub DoImportContentFile {
  my $self = shift;
  my( $filename, $data ) = @_;

  my $ds = $self->{datastore};

  StartLogSection( $self->{grabber_name} . " $filename", 1 );

  $ds->StartTransaction();
  
  $self->{earliestdate} = "2100-01-01";
  $self->{latestdate} = "1970-01-01";

  my $cref = $self->{filestore}->Get( $data->{xmltvid}, $filename );

  eval { $self->ImportContent( $file, $cref, $data ); };
  my( $message, $highest ) = EndLogSection( $self->{grabber_name} . 
					    " $filename" );
  if( $@ ) {
    $message .= $@;
    $highest = 5;
    $ds->Reset();
  }

  if( $highest > 3 ) {
    $ds->EndTransaction( 0 );

    $ds->sa->Update( "files", 
                     { channelid => $data->{id},
                       filename => $file, },
                     { successful => 0,
                       message => $message, } );
    
  }
  else { 
    $ds->EndTransaction( 1 );
  
    $ds->sa->Update( "files", 
                     { channelid => $data->{id},
                       filename => $file, },
                     { successful => 1,
                       message => $message,
                       earliestdate => $self->{earliestdate},
                       latestdate => $self->{latestdate},
                     } );
  
  }
}  

sub AddDate {
  my $self = shift;
  my( $date ) = @_;

  if( $date gt $self->{latestdate} ) {
    $self->{latestdate} = $date;
  }

  if( $date lt $self->{earliestdate} ) {
    $self->{earliestdate} = $date;
  }
}

sub RemoveMissing {
  my $self = shift;
  my( $ds, $chd ) = @_;

  my $sth = $ds->sa->Iterate( 'files', { channelid => $chd->{id} } );

  my $dir = $self->{conf}->{FileStore} . "/" . $chd->{xmltvid};

  while( my $data = $sth->fetchrow_hashref ) {

    if( not -f( $dir . "/" . $data->{filename} ) ) {
      progress( "Removing " . $dir . "/" . $data->{filename} );
      $ds->sa->Delete( 'files', { id => $data->{id} } );
    }
  }
}
  
sub ImportContentFile {
  my $self = shift;

  my( $filename, $chd ) = @_;

  die "You must override ImportContentFile";
}

sub md5sum {
  my( $file ) = @_;
  open(FILE, $file) or die "Can't open '$file': $!";
  binmode(FILE);
  
  return Digest::MD5->new->addfile(*FILE)->hexdigest;
}

1;
