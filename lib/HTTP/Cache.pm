package HTTP::Cache;

use strict;

=head1 NAME

HTTP::Cache

=head1 DESCRIPTION

An implementation of http get that keeps a local cache of fetched
pages to avoid fetching the same data from the server if it hasn't
been updated. The cache is stored on disk and is thus persistent
between invocations.

Uses the http-headers If-Modified-Since and ETag to let the server
decide if the version in the cache is up-to-date or not.

=head1 METHODS

=over 4

=cut

use LWP::UserAgent;
use HTTP::Request;
use Storable qw/lock_store lock_retrieve/;
use Digest::MD5 qw/md5_hex/;

# Each file in the BasePath-directory contains a stored perl hash
# containing
# {
#   url           => "http://whatever..."
#   last_modified => date,
#   etag          => etag,
#   last_accessed => now(),
#   content       => string,
# }

use vars qw(@ISA);

@ISA = qw();

=item new

Constructor that returns an HTTP::Cache object. Takes a single parameter
which is a hashref containing named arguments to the object.

  my $c = HTTP::Cache->new( { 
    BasePath  => "/tmp/cache", # Directory to store the cache in. 
    MaxAge    => 8*24,         # How many hours should items be kept in
                               # the cache after they were last accessed?
                               # Default is 8*24.
    Verbose   => 1,            # Print messages to STDERR. Default is 0.
    UserAgent => "my-spider",  # The user-agent string to use. Default
                               # is "perl-http-cache". 
   } );

The directory where the cache is stored must be writable. It must also only
contain files created by HTTP::Cache.

=cut 

sub new {
  my $proto = shift;
  my( $args ) = @_;
  
  my $class = ref($proto) || $proto;
  my $self  = {}; # $class->SUPER::new();
  $self->{BasePath} = $args->{BasePath} || die "Must specify a BasePath";
  $self->{Verbose} = $args->{Verbose} || 0;
  $self->{MaxAge} = $args->{MaxAge} || 8*24;
  $self->{UserAgent} = $args->{UserAgent} || "perl-http-cache";

  $self->{ua} = new LWP::UserAgent();
  $self->{ua}->agent( $self->{UserAgent} );

  bless ($self, $class);

  # Append a trailing slash if it is missing.
  $self->{BasePath} =~ s%([^/])$%$1/%;

  -d $self->{BasePath}
    or die $self->{BasePath} ."is not a directory"; 
   
  # Perl dies with a Segmentation fault if we try to do cleanup_cache()
  # from DESTROY, so we have to do it here.
  $self->cleanup_cache();

  return $self;
}

sub DESTROY
{
  my $self = shift;

  # Purge old entries from the cache.
  # $self->cleanup_cache();
}

=item get

Fetch a url from the server or from the cache if it hasn't been updated
on the server. Uses If-Modified-Since and ETag-headers in http to
let the server decide if the data in the cache is up-to-date.

  my( $content, $error ) = $c->get( $url );
  
  if( defined( $content ) )
  {
    # Data retrieved and stored in $content.
    # $error indicates if the data was found in the cache (0)
    # if it was fetched from the server but equal to the cache (1)
    # or if it was fetched from the server and different from the cache (2).
  }
  else
  {
    print STDERR "Failed to fetch $url. Error returned by server: $error";
  }

In scalar context, only $content is returned.

=cut

sub get
{
  my $self = shift;
  my( $url ) = @_;

  # Make sure that $url is a real string and not 
  # some kind of funky object that is automatically
  # converted to a string.
  $url = $url . "";
 
  print STDERR "Fetching $url " if $self->{Verbose};

  my $h = urlhash( $url );
  my $cachefile = $self->{BasePath} . $h;

  my $co;
  
  if( -s( $cachefile ) )
  {
    # Cache file exists.
    $co = lock_retrieve( $cachefile );

    if( $co->{url} ne $url )
    {
      print STDERR "\nCache collision between $url and $co->{url}\n";
      $co = undef;
    }
  }

  my $req = HTTP::Request->new( GET => $url );
  if( defined( $co ) )
  {
    $req->header( 
                  If_None_Match => $co->{etag},
                  If_Last_Modified => $co->{last_modified}
                );
  }
  
  my $res = $self->{ua}->request($req);
  if ($res->is_success) {
    $co->{etag} = $res->header('ETag');
    $co->{last_modified} = $res->header('Last-Modified');
    $co->{last_accessed} = time(); 
    $co->{url} = $url;

    if( exists($co->{content}) and
                ($res->content() eq $co->{content}) )
    {
      print STDERR "unchanged from server\n" if $self->{Verbose};
      lock_store( $co, $cachefile );
      return wantarray() ? ($co->{content}, 1 ) : $co->{content};
    }
    else
    {
      print STDERR "from server\n" if $self->{Verbose};
      $co->{content} = $res->content();
      lock_store( $co, $cachefile );
      return wantarray() ? ($co->{content}, 2 ) : $co->{content};
    }
  }
  elsif ( $res->code() eq '304' ) {
    print STDERR "from cache\n" if $self->{Verbose};

    $co->{last_accessed} = time();

    lock_store( $co, $cachefile );

    return wantarray() ? ($co->{content}, 0 ) : $co->{content};
  }
  else {
    my $mess = $res->code() . " " . $res->message();
    print STDERR "failed with error $mess\n" if $self->{Verbose};
    return wantarray() ? (undef, $mess ) : undef;
  }
}

sub cleanup_cache
{
  my $self = shift;

  my $now = time();

  foreach my $file (glob($self->{BasePath} . "*"))
  {
    my $co = lock_retrieve( $file );
    
    if( $now - $co->{last_accessed} 
        > $self->{MaxAge}*3600 )
    {
      print STDERR "Deleting $co->{url} from cache.\n" if $self->{Verbose};
      unlink $file;
    }
  }
}

sub urlhash
{
  my( $url ) = @_;

  return md5_hex( $url );
}

=head1 COPYRIGHT

Copyright (C) 2004 Mattias Holmlund. 

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

1;
