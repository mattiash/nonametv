package NonameTV::Importer::BaseFile;

use strict;
use warnings;

=pod

Abstract base-class for an Importer that uses data found in one directory
per channel where new files "magically appear" in the directory and must be
processed in the order that they appear.

=cut

use DateTime;
use POSIX qw/floor/;

use NonameTV::Log qw/info progress error logdie 
  log_to_string log_to_string_result/;

use NonameTV::Importer;

use base 'NonameTV::Importer';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{OptionSpec} = [ qw/force-update verbose+ remove-missing/ ];
    $self->{OptionDefaults} = { 
      'force-update' => 0,
      'verbose'      => 0,
      'remove-missing' => 0,
    };

    return $self;
}

sub Import {
  my $self = shift;
  my( $p ) = @_;
  
  NonameTV::Log::verbose( $p->{verbose} );

  my $ds = $self->{datastore};

  my $sth = $ds->Iterate( 'channels', { grabber => $self->{grabber_name} } )
      or logdie( "$self->{grabber_name}: Failed to fetch grabber data" );

  while( my $data = $sth->fetchrow_hashref ) {
    if( $p->{'remove-missing'} ) {
      $self->RemoveMissing( $ds, $data );
      next;
    }
    
    if( $p->{'force-update'} ) {
      # Delete all data for this channel.
      my $deleted = $ds->Delete( 'programs', { channel_id => $data->{id} } );
      progress( "Deleted $deleted records for $data->{xmltvid}" );
    }

    my $dir = $NonameTV::Conf->{FileStore} . "/" . $data->{xmltvid};
    my @files = split( "\n", qx/ls -t -r -1 $dir/ );
    
    foreach my $file (@files) {
      my $md5 = md5sum( "$dir/$file" );
      my $fdata = $ds->Lookup( "files", { channelid => $data->{id},
                                          filename => $file } );
      
      if( defined( $fdata ) and ($fdata->{md5sum} ne $md5) ) {
        # The file has changed since we last saw it. 
        # Treat it as a new file.

        $ds->Delete( "files", { channelid => $data->{id},
                                filename => $file } );
      
        $fdata = undef;
      }

      if( defined( $fdata ) ) {
        # We have seen this file before
        next unless $p->{'force-update'};
        $ds->Delete( "files", { channelid => $data->{id},
                                filename => $file } );
      }

      $ds->Add( "files", { channelid => $data->{id},
                           filename => $file,
                           'md5sum' => $md5,
                         } );
      
      $self->DoImportContentFile( "$file", $data );
    }

  }

  $sth->finish();
}

sub DoImportContentFile {
  my $self = shift;
  my( $file, $data ) = @_;

  my $ds = $self->{datastore};

  # Log ERROR and FATAL
  my $h = log_to_string( 4 );

  $ds->DoSql( "START TRANSACTION" );
  
  $self->{earliestdate} = "2100-01Ã-01";
  $self->{latestdate} = "1970-01-01";

  # Import file
  my $dir = $NonameTV::Conf->{FileStore} . "/" . $data->{xmltvid};
  eval { $self->ImportContentFile( "$dir/$file", $data ); };
  my( $message, $highest ) = log_to_string_result( $h );
  if( $@ ) {
    $message .= $@;
    $highest = 5;
    $ds->Reset();
  }

  if( $highest > 3 ) {
    $ds->DoSql("Rollback");

    $ds->Update( "files", 
                 { channelid => $data->{id},
                   filename => $file, },
                 { successful => 0,
                   message => $message, } );
    
  }
  else { 
    $ds->DoSql("Commit");
  
    $ds->Update( "files", 
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

  my $sth = $ds->Iterate( 'files', { channelid => $chd->{id} } );

  my $dir = $NonameTV::Conf->{FileStore} . "/" . $chd->{xmltvid};

  while( my $data = $sth->fetchrow_hashref ) {

    if( not -f( $dir . "/" . $data->{filename} ) ) {
      progress( "Removing " . $dir . "/" . $data->{filename} );
      $ds->Delete( 'files', { id => $data->{id} } );
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
