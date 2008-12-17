#!/usr/bin/perl -w

use utf8;

use strict;

use FindBin;
use lib "$FindBin::Bin/../lib";

use File::Temp qw/tempdir/;

use Test::More tests => 16;

BEGIN { 
  use_ok( 'NonameTV::FileStore' ); 
}

my $path = tempdir( CLEANUP => 1 );
my $xmltvid = "p1.sr.se";

{
  my $fs = NonameTV::FileStore->new( 
    { Path => $path } );
  
  $fs->AddFile( $xmltvid, "test", \ "Helloåäö" );
  
  my @files = $fs->ListFiles( $xmltvid );
  is( scalar( @files ), 1, "ListFiles - Correct number of files" );
  is( $files[0][0], 'test', "ListFiles - Correct filename" );

  my $cref = $fs->GetFile( $xmltvid, "test" );
  is( $$cref, "Helloåäö", "GetFile - Correct content" );
}

{
  my $fs = NonameTV::FileStore->new( 
    { Path => $path } );
  
  my @files = $fs->ListFiles( $xmltvid );
  is( scalar( @files ), 1, "ListFiles Persistent - Correct number of files" );
  is( $files[0][0], 'test', "ListFiles Persistent - Correct filename" );

  my $cref = $fs->GetFile( $xmltvid, "test" );
  is( $$cref, "Helloåäö", "GetFile Persistent - Correct content" );
}

{
  my $fs = NonameTV::FileStore->new( 
    { Path => $path } );
  
  my @files = $fs->ListFiles( $xmltvid );
  my $md5 = $files[0][1];
  my $ts = $files[0][2];
  
  $fs->RecreateIndex( $xmltvid );
    
  @files = $fs->ListFiles( $xmltvid );
  is( scalar( @files ), 1, "RecreateIndex - Unchanged number of files" );
  is( $files[0][0], 'test', "RecreateIndex - Unchanged filename" );
  is( $files[0][1], $md5, "RecreateIndex - Unchanged md5" );
  is( $files[0][2], $ts, "RecreateIndex - Unchanged timestamp" );

  $fs->AddFile( $xmltvid, "test", \ "Helloåäö" );
  
  @files = $fs->ListFiles( $xmltvid );
  is( scalar( @files ), 1, "ReAdd - Unchanged number of files" );
  is( $files[0][0], 'test', "ReAdd - Unchanged filename" );
  is( $files[0][1], $md5, "ReAdd - Unchanged md5" );
  is( $files[0][2], $ts, "ReAdd - Unchanged timestamp" );
}


{
  my $fs = NonameTV::FileStore->new( 
    { Path => $path } );

  $fs->AddFile( $xmltvid, "test2", \ "Hello" );
  my @files = $fs->ListFiles( $xmltvid );
  is( scalar( @files ), 2, "Two files after adding second file" );
}
