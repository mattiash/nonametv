#!/usr/bin/perl -w

use utf8;

use strict;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Test::More tests => 4;

BEGIN { 
    use_ok( 'NonameTV::Language', qw/LoadLanguage/ ); 
    use_ok( 'NonameTV::Factory', qw/CreateDataStore/ ); 
}

my $ds = CreateDataStore();

my $lng = LoadLanguage( "sv", "exporter-xmltv", $ds );

is( ref($lng), "HASH" );
is( $lng->{episode_season}, "säsong" );
