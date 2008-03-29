package NonameTV::ContentCache;

use strict;

use Digest::MD5 qw/md5_hex/;
use Encode qw(encode_utf8);

use LWP::UserAgent;

=pod

Utility class for NonameTV.

Downloads data via http. 

 1. Intermittent errors on a server that occur when fetching content.
 2. Intermittent and persistent error that occur before the content
    is fetched. E.g. login to the site fails.
 3. Files change even though the interesting content hasn't changed.
    E.g. html-files with advertisements.
 4. Downloaded files contain errors and need to be overridden.
 5. The url for a specific object may change, which means that a 
    normal http-cache is not useful.
 
The NonameTV::ContentCache class solves all these problems. It does this
by implementing a cache with stored responses and keeps track of when
an error first occured and if we have told the user about it. The key into
the cache is the objectname and not the url.


TODO:

Implement some way of purging old data.

Implement overrides using

  nonametv-contentcache <namespace> add <objname> <filename>
  nonametv-contentcache <namespace> addfiltered <objname> <filename>
  nonametv-contentcache <namespace> remove <objname>

=cut 

=pod

=head1 Constructor

  my $cc = NonameTV::ContentCache->new( {
    basedir => "/tmp/test",
    callbackobject => $obj,
    useragent => "Mozilla 1.0",
    warnafter => 23*60*60, # Warn after an error has persisted
                           # for this many seconds
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

  $self->{ua} = $ua;

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
  (undef, undef) - Can be returned for three different reasons:
     1. The content or filtered content was the same as the last time 
        it was downloaded.
     2. The download failed, but it hasn't failed for long enough to 
        notify the user.
     3. The download failed, but we have previously notified the user of this
        and don't need to do it again.

     If $force is true, the content is returned in (1) and the errormessage
     in (2) and (3).

=cut
 
sub GetContent {
  my $self = shift;
  my( $objectname, $data, $force ) = @_;

  $force = 0 if not defined $force;
  
  my $co = $self->{callbackobject};
  
  my( $url, $error ) = $co->Object2Url( 
    $objectname, $data );
  if( not defined( $url ) ) {
    return( undef, 
	    $self->ReportError( $objectname, $error, $force ) );
   }

  my $res = $self->{ua}->get( $url );

  if( $res->is_success ) {
    $self->TouchState( $objectname );
    my $state = $self->GetState( $objectname );
    
    my $currstate = {};

    if( $force ) {
      $state->{contentmd5} = "xx";
      $state->{filteredmd5} = "xx";
    }

    # Filter content
    # We need to do this before comparing md5sums, since otherwise errors
    # from the filter would never be reported if the content filter fails
    # and the content never changes after that.
    my( $filtered_ref, $filter_error ) = 
	$co->FilterContent( $res->content_ref, $data );

    if( not defined $filtered_ref ) {
      return (undef,
	      $self->ReportError( $objectname, $filter_error, $force ) );
    }

    # Calculate md5sum of content
    my $contentmd5 = $self->CalculateMD5( $res->content_ref );

    # Compare md5sum with stored md5sum
    if( $contentmd5 eq $state->{contentmd5} ) {
      # Same as last time
      return (undef, undef);
    }

    $self->WriteReference( $self->Filename( $objectname, "content",
                           $co->ContentExtension() ), 
			   $res->content_ref );

    $currstate->{contentmd5} = $contentmd5;

    # Calculate md5sum of filtered content
    my $filteredmd5 = $self->CalculateMD5( $filtered_ref );
    $currstate->{filteredmd5} = $filteredmd5;

    $self->SetState( $objectname, $currstate );

    # Compare md5sum with stored md5sum
    if( $filteredmd5 eq $state->{filteredmd5} ) {
      # Same as last time
      return (undef, undef);
    }

    $self->WriteReference( $self->Filename( $objectname, "filtered", 
                                            $co->FilteredExtension() ), 
			   $filtered_ref );
    

    return ($filtered_ref, undef);
  }
  else {
    return (undef, 
	    $self->ReportError( $objectname, $res->status_line(), $force ) );
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
  my $res = $self->{ua}->get( $url );
  
  if( $res->is_success ) {
    return ($res->content_ref, undef);
  }
  else {
    return (undef, $res->status_line);
  }
}

=pod

Returns the errormessage if it needs to be shown to the user and undef
otherwise.

=cut

sub ReportError {
  my $self = shift;
  my( $objectname, $errormessage, $force ) = @_;

  $force = 0 if not defined $force;

  $self->TouchState( $objectname );
  my $state = $self->GetState( $objectname );

  if( $force ) {
    my $currstate;
    $currstate->{firstfail} = $state->{firstfail} == 0 ? 
	time : $state->{firstfail};

    $currstate->{warnfailed} = 1;
    $self->SetState( $objectname, $currstate );
    return $errormessage;
  }    
  elsif( $state->{firstfail} == 0 ) {
    # This is the first time this object failed.
    my $currstate;
    $currstate->{firstfail} = time;
    $self->SetState( $objectname, $currstate );
    return undef;
  }
  elsif( time - $state->{firstfail} < $self->{warnafter} ) {
    # This object first failed less than 23 hours ago.
    return undef;
  }
  elsif( $state->{warnfailed} ) {
    # We have already warned that this object failed.
    return undef;
  }
  else {
    my $currstate;
    $currstate->{firstfail} = $state->{firstfail};
    $currstate->{warnfailed} = 1;
    $self->SetState( $objectname, $currstate );      
    return $errormessage;
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
firstfail 174616182 (unix timestamp)
warnfailed 0

=cut

sub GetState {
  my $self = shift;
  my( $objectname ) = @_;

  my $state = {
    contentmd5 => "x",
    filteredmd5 => "x",
    firstfail => 0,
    warnfailed => 0,
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
