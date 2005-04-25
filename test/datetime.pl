#!/usr/bin/perl -w

use strict;

use DateTime;
use DateTime::Span;
use DateTime::SpanSet;

my $dt1 = DateTime->new( year => 2004, month => 12, day => 1 );
my $dt2 = DateTime->new( year => 2004, month => 12, day => 2 );

my $span1 = DateTime::Span->from_datetime_and_duration(
    start => $dt1, days => 1 );
my $span2 = DateTime::Span->from_datetime_and_duration(
    start => $dt2, days => 1 );

my $spanset = DateTime::SpanSet->empty_set();
$spanset = $spanset->union( $span1 );
$spanset = $spanset->union( $span2 );

my $iter = $spanset->iterator;
while ( my $dt = $iter->next ) {
        # $dt is a DateTime::Span
  print $dt->start->ymd . " -> " .$dt->end->ymd . "\n";
};

$iter = $spanset->iterator;
while ( my $dt = $iter->next ) {
  # $dt is a DateTime::Span
  my $date = $dt->start;
  do
  {
    print $date->ymd('-') . "\n";
    $date = $date->add( days => 1 );
  } until $date >= $dt->end;
}

