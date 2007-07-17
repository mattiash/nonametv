package NonameTV::ContentCache;

use strict;

use Digest::MD5 qw/md5_hex/;
use Encode qw(encode_utf8);

use LWP::UserAgent;

=pod
    
    my $cc = new NonameTV::ContentCache( { basedir => "/tmp/test" } );

    my( $dataref, $error ) = $cc->GetUrl( $url );

    my $dataref = $cc->GetContent( $objectname, $url, $filtersub, $force );

Keeps a cache indexed by namespace and objectname. Returns a reference to
the data returned by filtersub or undef if the data was unchanged or
retrieval failed. force=1 means always return data even if it is unchanged.

  1. Fetch the url.
  2. Run the returned data through filtersub if it exists.
  3. Compare the output of filtersub with the stored md5sum associated
     with (namespace, objectname).

Implement some way of purging old data.

Warn if download for an object fails for more than 24 hours.

Implement overrides using

  nonametv-contentcache <namespace> add <objname> <filename>
  nonametv-contentcache <namespace> addfiltered <objname> <filename>
  nonametv-contentcache <namespace> remove <objname>

=cut 

sub new {
  my $class = ref( $_[0] ) || $_[0];
  
  my $self = { }; 
  bless $self, $class;

  # Copy the parameters supplied in the constructor.
  foreach my $key (keys(%{$_[1]})) {
      $self->{$key} = ($_[1])->{$key};
  }

  my $ua = LWP::UserAgent->new( agent => "Grabber from http://tv.swedb.se", 
				cookie_jar => {} );

  $self->{ua} = $ua;

  return $self;
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

    my $dataref = $cc->GetContent( $objectname, $url, $filtersub, $force );

Fetch a an object from a url. Returns undef if the object was unchanged
since the last time it was fetched or if the fetch failed. The caller
does not need to print an error-message if undef is returned, this is
handled by GetContent.

If $filtersub is defined, the downloaded content is run through filtersub
before it is compared to the data downloaded previously and returned.

If $force is true, data is always returned if it can be downloaded. 

=cut
 
sub GetContent {
  my $self = shift;
  my( $objectname, $url, $filtersub, $force ) = @_;

  $filtersub = sub { return $_[0] } if not defined $filtersub;
  $force = 0 if not defined $force;

  my $res = $self->{ua}->get( $url );

  $self->TouchState( $objectname );
  my $state = $self->GetState( $objectname );

  my $currstate = {};

  if( $res->is_success ) {
    if( $force ) {
      $state->{contentmd5} = "xx";
      $state->{filteredmd5} = "xx";
    }

    # Calculate md5sum of content
    my $contentmd5 = $self->CalculateMD5( $res->content_ref );

    # Compare md5sum with stored md5sum
    if( $contentmd5 eq $state->{contentmd5} ) {
      # Same as last time
      return undef;
    }

    $currstate->{contentmd5} = $contentmd5;

    # Filter content
    my $filtered_ref = &{$filtersub}( $res->content_ref );

    # Calculate md5sum of filtered content
    my $filteredmd5 = $self->CalculateMD5( $filtered_ref );
    $currstate->{filteredmd5} = $filteredmd5;

    $self->SetState( $objectname, $currstate );

    # Compare md5sum with stored md5sum
    if( $filteredmd5 eq $state->{filteredmd5} ) {
      # Same as last time
      return undef;
    }

    return $filtered_ref;
  }
  else {
    if( $state->{firstfail} == 0 ) {
      # This is the first time this object failed.
      my $currstate;
      $currstate->{firstfail} = time;
      $self->SetState( $objectname, $currstate );
    }
    elsif( time - $state->{firstfail} < 23*60*60 ) {
      # This object first failed less than 23 hours ago.
    }
    elsif( $state->{warnfailed} ) {
      # We have already warned that this object failed.
    }
    else {
      print STDERR "$objectname failed.\n";
      my $currstate;
      $currstate->{firstfail} = $state->{firstfail};
      $currstate->{warnfailed} = 1;
      $self->SetState( $objectname, $currstate );      
    }

    return undef;
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

  my $statefile = $self->StateFile( $objectname );
  open( IN, "< $statefile" ) or return $state;

  while( my $line = <IN> ) {
    my( $key, $data ) = ($line =~ /^(.*?) (.*?)$/);
    $state->{$key} = $data;
  }

  close( IN );
  return $state;
}

sub SetState {
  my $self = shift;
  my( $objectname, $state ) = @_;

  my $statefile = $self->StateFile( $objectname );

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

sub StateFile {
  my $self = shift;
  my( $objectname ) = @_;

  return "$self->{basedir}/$objectname.state";
}

sub TouchState {
  my $self = shift;
  my( $objectname ) = @_;

  my $now = time;
  utime( $now, $now, $self->StateFile( $objectname ) );
}

1;
