#!/usr/bin/perl -w

use utf8;

use strict;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Test::More tests => 5;

BEGIN { 
    use_ok( 'NonameTV', qw/expand_entities Html2Xml/ ); 
}

is( expand_entities( 'ab' ), 'ab' );
is( expand_entities( 'a&#257;' ), 'aä' );
is( expand_entities( 'a&#8212; &#8230;b' ), 'a-- ...b' );

my $doc;

eval {
    $doc = Html2Xml( << 'EOHTML' );
<html>
  <body>
    <h1>Test</h1>
  </body>
</html>
	
EOHTML

};

isa_ok( $doc, "XML::LibXML::Document" );
