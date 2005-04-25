#!/usr/bin/perl -w

use strict;

use XML::LibXML;

my( $file ) = @ARGV;

my $content;

{
  local(*INPUT, $/);
  open (INPUT, $file)     || die "can't open $file: $!";
  $content = <INPUT>;
}

my $xml = XML::LibXML->new;
my $doc = $xml->parse_string($content);
