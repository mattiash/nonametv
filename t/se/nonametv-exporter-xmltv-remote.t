#!/usr/bin/perl -w

# Test a site that provides data in xmltv-format.

use utf8;
use strict;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Test::More;

use HTTP::Cache::Transparent;
use LWP::UserAgent;
use File::Temp qw/tempdir/;

my @roots = qw%
  http://tv.swedb.se/xmltv
  http://xmltv1.tvsajten.com/xmltv
  http://xmltv2.tvsajten.com/xmltv
  http://xmltv.tvsajten.com/xmltv
    %;    

plan tests => scalar(@roots) * 7;

my $ua = LWP::UserAgent->new;

my @content;

foreach my $root (@roots) {
  my $response = $ua->get("$root/channels.xml.gz");

  is( $response->code, 200, "$root 200 OK" );
  push @content, $response->content;

  is( $response->header( 'Content-Type' ), "application/xml", "$root Content-Type" );
  is( $response->header( 'Content-Encoding' ), "gzip", "$root Content-Encoding" );
}

for( my $i=0; $i < scalar( @roots ); $i++ ) {
  ok( length($content[$i]) > 100, "$roots[$i] content length > 100" );
  ok( $content[0] eq $content[$i], "$roots[$i] same content" );
}
  
HTTP::Cache::Transparent::init( {
  BasePath => tempdir( CLEANUP => 1 ),
} );

foreach my $root (@roots) {
  my $ua2 = LWP::UserAgent->new;
  
  my $r1 = $ua2->get("$root/channels.xml.gz");
  is( $r1->header( 'X-Cached' ), undef, "$root first fetch not cached" );
  
  my $r2 = $ua2->get("$root/channels.xml.gz");
  is( $r2->header( 'X-Cached' ), 1, "$root second fetch cached" );
}
