#!/usr/bin/perl -w

use utf8;

use strict;

use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw/tempfile/;

use Test::More tests => 15;

BEGIN { 
    use_ok( 'NonameTV', 
	    qw/expand_entities Html2Xml Htmlfile2Xml norm
	    AddCategory/ ); 
}

is( expand_entities( 'ab' ), 'ab' );
is( expand_entities( 'a&#257;' ), 'aä' );
is( expand_entities( 'a&#8212; &#8230;b' ), 'a-- ...b' );

my $html = << 'EOHTML';
<html>
  <body>
    <h1>Test</h1>
  </body>
</html>
	
EOHTML

my $doc = Html2Xml( $html );

isa_ok( $doc, "XML::LibXML::Document" );

my( $fh, $fn ) = tempfile();
print $fh $html;
close $fh;

my $doc2 = Htmlfile2Xml( $fn );

isa_ok( $doc2, "XML::LibXML::Document" );

is( norm( "  a  b\n cd" ), "a b cd", "norm()" );


my $ce = {};

AddCategory( $ce, undef, undef );
is( $ce->{program_type}, undef );
is( $ce->{category}, undef );

AddCategory( $ce, "test", undef );
is( $ce->{program_type}, "test" );
is( $ce->{category}, undef );

AddCategory( $ce, undef, "testcat" );
is( $ce->{program_type}, "test" );
is( $ce->{category}, "testcat" );

AddCategory( $ce, "error", "error" );
is( $ce->{program_type}, "test" );
is( $ce->{category}, "testcat" );


