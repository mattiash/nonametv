#!/usr/bin/perl -w

use utf8;

use strict;

use FindBin;
use lib "$FindBin::Bin/../lib";

use File::Temp qw/tempdir/;

use Test::More tests => 15;

BEGIN { 
    use_ok( 'NonameTV::FileStore' ); 
}

my $path = tempdir( CLEANUP => 1 );

my $fs = NonameTV::FileStore->new( 
	{ Path => $path } );

my $content = "Helloåäö";

$fs->AddFile( "p1.sr.se", "test", \$content );

my @files = $fs->ListFiles( "p1.sr.se" );
is( scalar( @files ), 1 );
is( $files[0][0], 'test' );

my $md5 = $files[0][1];
my $ts = $files[0][2];

$fs->RecreateIndex( "p1.sr.se" );

@files = $fs->ListFiles( "p1.sr.se" );
is( scalar( @files ), 1 );
is( $files[0][0], 'test' );
is( $files[0][1], $md5 );
is( $files[0][2], $ts );

my $c2 = "Helloåäö";

$fs->AddFile( "p1.sr.se", "test", \$c2 );

@files = $fs->ListFiles( "p1.sr.se" );
is( scalar( @files ), 1 );
is( $files[0][0], 'test' );
is( $files[0][1], $md5 );
is( $files[0][2], $ts );

$fs->AddFile( "p1.sr.se", "test2", \$c2 );
@files = $fs->ListFiles( "p1.sr.se" );
is( scalar( @files ), 2 );

{
  my $cref = $fs->GetFile( "p1.sr.se", "test" );
  is( $$cref, "Helloåäö" );
}

$fs = undef;

$fs = NonameTV::FileStore->new( 
    { Path => $path } );

{
  my $cref = $fs->GetFile( "p1.sr.se", "test" );
  is( $$cref, "Helloåäö" );
}

$fs->AddFile( "p1.sr.se", "test3", \$c2 );

$fs = undef;

$fs = NonameTV::FileStore->new( 
    { Path => $path } );

{
  my $cref = $fs->GetFile( "p1.sr.se", "test3" );
  is( $$cref, "Helloåäö" );
}
