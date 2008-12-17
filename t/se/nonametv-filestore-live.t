#!/usr/bin/perl -w

# Test that 00files is newer than all files.

use strict;

use Test::More qw/no_plan/;

use FindBin;
use lib "$FindBin::Bin/../../lib";

use NonameTV::Config;

my $conf = NonameTV::Config::ReadConfig();

ok( defined( $conf ) );
ok( defined( $conf->{FileStore} ) );
ok( -d $conf->{FileStore} );

my @dirs = glob( "$conf->{FileStore}*" );
foreach my $dir (@dirs) {
    ok( -d $dir, "$dir is a directory" );
    next if not -d $dir;
    ok( -s "$dir/00files", "$dir/00files is non-zero" );
    my $updated = -M "$dir/00files";
    my $newest = $updated;
    foreach my $file (glob("$dir/*")) {
	$newest = -M $file if( -M $file < $newest );
    }
    ok( $newest == $updated, "$dir updated" );
}

