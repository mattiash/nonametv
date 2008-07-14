package NonameTV::ContentCache;

use strict;

use Digest::MD5 qw/md5_hex/;
use Encode qw(encode_utf8);

use LWP::UserAgent;

=pod

Utility class for NonameTV.

Downloads data via http and stores it in a cache. The cache is stored
as plain files named after the objectname, which makes it easy to look
at the contents of the cache and inspect the data that has been
downloaded.

=pod

=head1 Constructor

  my $cc = NonameTV::ContentCache->new( {
    basedir => "/tmp/test",
    callbackobject => $obj,
    useragent => "Mozilla 1.0",
  } );

The callbackobject must implement the following methods:

  my( $urlstr, $error ) = $co->Object2Url( $objectname, $callbackdata );

  Convert an objectname into a url. The callbackdata is taken from
  the call to GetConvert.

  my( $filtered_ref, $error ) = $co->FilterContent( $content_ref, 
                                                    $callbackdata )

  Filter the content to remove any unnecessary data. The resulting data
  is compared to the previous filtered data to see if the filtered data
  has changed before it is returned by GetContent.

  Both these methods can return (undef, "errorstring") if an error 
  occured for some reason. The error will be handled in the same way as
  errors from the http-server.

  my( $extension ) = $co->ContentExtension();
  my( $extension ) = $co->FilteredExtension();

  ContentCache will name the files on disk with these extension (e.g. html).
  If undef is returned, no extension is used.

=cut

sub new {
  my $class = ref( $_[0] ) || $_[0];
  
  my $self = { }; 
  bless $self, $class;

  # Copy the parameters supplied in the constructor.
  foreach my $key (keys(%{$_[1]})) {
      $self->{$key} = ($_[1])->{$key};
  }

  my $ua = LWP::UserAgent->new( agent => $self->{useragent}, 
				cookie_jar => {} );

  if( not defined $self->{credentials} ) {
    $self->{credentials} = {};
  }

  $self->{ua} = $ua;

  if( not -d $self->{basedir} ) {
      mkdir( $self->{basedir} ) or
	  die "Failed to create $self->{basedir}";
  }

  return $self;
}

=pod

    my( $dataref, $errormsg ) = $cc->GetContent( $objectname, 
                                                 $callbackdata, 
                                                 $force );

Fetch a an object from a url. Returns undef if the object was unchanged
since the last time it was fetched or if the fetch failed. $errormsg
contains an errormessage returned from the server. Three different answers
are possible:

  (dataref, undef) - Data was downloaded and needs to be processed.
  (undef, errormsg) - Download failed and the caller should notify the user
                      of the error.
  (undef, undef) - The content or filtered content was the same as the last time 
        it was downloaded.

     If $force is true, (undef, undef) is never returned.

=cut
 
sub GetContent {
  my $self = shift;
  my( $objectname, $data, $force ) = @_;

  $force = 0 if not defined $force;
  
  my $co = $self->{callbackobject};
  
  my( $url, $objerror ) = $co->Object2Url( $objectname, $data );
  if( not defined( $url ) ) {
    return( undef, $objerror );
   }

  my( $cref, $geterror ) = $self->GetUrl( $url );

  if( defined( $cref ) ) {
    $self->TouchState( $objectname );
    my $state = $self->GetState( $objectname );
    
    my $currstate = {
      contentmd5 => "(unknown)",
      filteredmd5 => "(unknown)",
    };

    if( $force ) {
      $state->{contentmd5} = "xx";
      $state->{filteredmd5} = "xx";
    }

    # Calculate md5sum of content
    $currstate->{contentmd5} = $self->CalculateMD5( $cref );

    # Compare md5sum with stored md5sum
    if( $currstate->{contentmd5} eq $state->{contentmd5} ) {
      # Same as last time
      return (undef, undef);
    }

    $self->WriteReference( $self->Filename( $objectname, "content",
                           $co->ContentExtension() ), 
			   $cref );

    # Filter content
    if( (not defined $cref) or (not defined $$cref) ) {
      my $empty = "";
      $cref = \$empty;
    }

    my( $filtered_ref, $filter_error ) = 
	$co->FilterContent( $cref, $data );

    if( not defined $filtered_ref ) {
      $self->SetState( $objectname, $currstate );
      return (undef, $filter_error );
    }

    # Calculate md5sum of filtered content
    $currstate->{filteredmd5} = $self->CalculateMD5( $filtered_ref );

    $self->SetState( $objectname, $currstate );

    # Compare md5sum with stored md5sum
    if( $currstate->{filteredmd5} eq $state->{filteredmd5} ) {
      # Same as last time
      return (undef, undef);
    }

    $self->WriteReference( $self->Filename( $objectname, "filtered", 
                                            $co->FilteredExtension() ), 
			   $filtered_ref );
    
    return ($filtered_ref, undef);
  }
  else {
    return (undef, $geterror );
  }
}

=pod

  my( $dataref, $error ) = $cc->GetUrl( $url );

Fetch a url. Returns (undef, "error message")  if the server 
returned an error.

=cut
 
sub GetUrl {
  my $self = shift;
  my( $url ) = @_;

  my $surl = $url;
  my( $host )  = ($surl =~ m%://(.*?)/%);
  if( defined( $self->{credentials}->{$host} ) ) {
    my $cred = $self->{credentials}->{$host};
    
    $surl =~ s%://(.*?)/%://$cred\@$1/%;
  }

  my $res = $self->{ua}->get( $surl );
  
  if( $res->is_success ) {
    return ($res->content_ref, undef);
  }
  else {
    return (undef, $res->status_line);
  }
}

=pod

Content is stored in both filtered and unfiltered format. Each content
uses a number of files:

 objname.unfiltered
 objname.filtered
 objname.state

objname.state is touch()ed each time the content is asked for.
objname.state contains the following:

contentmd5 abdb4b1b3ba
filteredmd5 ab3b2b4b1b4

=cut

sub GetState {
  my $self = shift;
  my( $objectname ) = @_;

  my $state = {
    contentmd5 => "x",
    filteredmd5 => "x",
  };

  my $statefile = $self->Filename( $objectname, "state" );
  open( IN, "< $statefile" ) or return $state;

  while( my $line = <IN> ) {
    next if $line =~ /^\s+$/;
    my( $key, $data ) = ($line =~ /^(.*?) (.*?)$/);
    $state->{$key} = $data;
  }

  close( IN );
  return $state;
}

sub SetState {
  my $self = shift;
  my( $objectname, $state ) = @_;

  my $statefile = $self->Filename( $objectname, "state" );

  open( OUT, "> $statefile" )
      or die "Failed to write to $statefile";

  foreach my $key (keys %{$state}) {
    print OUT "$key $state->{$key}\n";
  }

  close( OUT );
}

sub CalculateMD5 {
  my $self  = shift;
  my( $strref ) = @_;

  return md5_hex(encode_utf8($$strref));
}

sub Filename {
  my $self = shift;
  my( $objectname, $type, $extension ) = @_;
  
  if( defined( $extension ) ) {
    $extension = ".$extension";
  }
  else {
    $extension = "";
  }

  if( $type eq "state" ) {
    return "$self->{basedir}/$objectname.state";
  }
  elsif( $type eq "content" ) {
    return "$self->{basedir}/$objectname.content$extension";
  }
  elsif( $type eq "filtered" ) {
    return "$self->{basedir}/$objectname.filtered$extension";
  }
  die "Unknown type $type";
}

sub TouchState {
  my $self = shift;
  my( $objectname ) = @_;

  my $now = time;
  utime( $now, $now, $self->Filename( $objectname, "state" ) );
}

sub WriteReference {
  my $self = shift;

  my( $filename, $ref ) = @_;

  open OUT, "> $filename" or die "Failed to write to $filename";
  print OUT $$ref;
  close( OUT );
}

sub RemoveOld {
  my $self = shift;

  my $g = $self->Filename( "*", "state" );

  my @statefiles = glob( $g );

  foreach my $statefile (@statefiles) {
    if( -M( $statefile ) > 7 ) {
      my( $base ) = ($statefile =~ /(.*)\.state$/);

      unlink( $statefile );
      unlink <$base.content*>;
      unlink <$base.filtered*>;
    }
  }
}

1;
