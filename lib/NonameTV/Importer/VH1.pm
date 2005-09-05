# $Id: VH1.pm,v 1.6 2005/09/05 11:30:47 frax Exp $
package NonameTV::Importer::VH1;

use strict;
use warnings;

=pod

Import data from Word-files delivered via e-mail.  

Observe that the year is not presented in the data provided by
VH-1. This module tries to get the year from the filename or if not
possible try to guess it. This can be overridden by setting the year
variable in the constructor.

Features:

=cut

use DateTime;

use NonameTV qw/Wordfile2HtmlTree Htmlfile2HtmlTree Utf8Conv/;
use NonameTV::DataStore::FilePrint;
use NonameTV::DataStore::Helper;
# frax -- replace above ln with next ln: 
#use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error logdie/;

use NonameTV::Importer;
use base 'NonameTV::Importer';

use HTML::TreeBuilder;
use HTML::Entities; 


sub new 
{
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new(@_);
  bless ($self, $class);
  
  my $dsh= NonameTV::DataStore::Helper->new(NonameTV::DataStore::FilePrint->new(new IO::File ">&STDOUT"), 
					    'Europe/Stockholm');
  # frax -- replace above ln with next ln: 
  #my $dsh=  NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  # Set the below to an interger in the range 2000 - 2999 to
  # override automatic year detection (could be sent as a parameter
  # to this constructor or to the ImportFile method, but I leave
  # that to Mattias to decide.
  $self->{year} = undef;

  $self->{xmltvid}= 'vh1.com';
  $self->{channel_data}->{'vh1.com'} = { id => 'vh1id' };
  # frax -- replace above with next replace region:
  ### frax -- replace region ###
  #my $sth = $self->{datastore}->Iterate( 'channels', 
  #                                       { grabber => 'vh1' },
  #                                       qw/xmltvid id grabber_info/ )
  #    or &logdie("Failed to fetch grabber data");
  #
  #while( my $data = $sth->fetchrow_hashref )
  #{
  #  $self->{channel_data}->{$data->{xmltvid}} = 
  #  { id => $data->{id}, };
  #}
  #$sth->finish;
  ### frax -- eo replace region ###

  $self->{OptionSpec} = [ qw/verbose/ ];
  $self->{OptionDefaults} = { 
    'verbose' => 0,
  };
  
  # frax -- Logfile should probably not be initiated here
  NonameTV::Log::init({LogFile => '/dev/console'});
  
  return $self;
}


sub Import
{
  my $self = shift;
  my( $p ) = @_;

  foreach my $file (@ARGV)
  {
    &progress("VH1: Processing \"$file\"");
    $self->ImportFile( "", $file, $p );
  }
}


sub ImportFile
{
  my $self= shift;
  my ($contentname, $file, $p)= @_;

  my $channel_id= $self->{channel_data}->{$self->{xmltvid}}->{id};

  my $dsh= $self->{datastorehelper};

  my $tree;
  if($file =~  m/\.doc$/i) 
  {
    $tree= &Wordfile2HtmlTree($file);
  }
  elsif($file =~ /\.html$/) 
  {
    $tree= &Htmlfile2HtmlTree($file);
  }
  else 
  {
    &error("VH1: Unknown extension \"$file\"");
  }

  if(!defined $tree) 
  {
    &error("VH1: \"$file\" failed to parse");
    return;
  }

  # Some statics used more then once
  my %monthno= ( january => 1, february => 2, march => 3, april => 4, may => 5,
		 june => 6, july => 7, august => 8, september => 9,
		 october => 10, november => 11, december => 12 );
  my $month= join '|', keys %monthno;
  my %weekdayno= ( monday => 1, tuesday => 2, wednesday => 3, thursday => 4,
		   friday => 5, saturday => 6, sunday => 7 ); 
  my $weekday= join '|', keys %weekdayno;

  # Automatic year detection, first try -- from filename
  # If this fails the current year will be used if the current month
  # is less than or equal to the chart month, otherwise the next year is used
  if(!defined( $self->{year} ) && $file =~ m/($month)[ _]*(2[0-9]{3})/i)
  {
    $self->{year}= $2;
  }

  # Lets find those schedules
  for my $e ($tree->look_down('_tag', 'p', sub { $_[0]->as_text() =~ m/^\s*($weekday)\s*[0-9][0-9]?\s*($month)\s*$/i }) ) 
  {
    $e->as_text() =~ m/^\s*($weekday)\s*([0-9][0-9]?)\s*($month)\s*$/i
	or &logdie("This should not happen if the regexps are correct!");
    my $wday= $weekdayno{lc($1)};
    my $mday= $2;
    my $mno= $monthno{lc($3)};
    my $year= $self->{year};

    # Guess year?
    unless(defined $year) 
    {
      ($year, my $cmonth) = split /-/, DateTime->now->ymd('-');
      ++$year if $mno < $cmonth; # probably importing for next year
    }
    
    my $date= undef;
    eval 
    {
      $date= DateTime->new(year => $year, 
			   month => $mno,
			   day => $mday,
			   time_zone => 'Europe/Stockholm'); 
    };
    # Consistency check
    unless(defined $date) 
    { 
      &error('WARNING! Invalid date "'.&norm($e->as_text()).
	     "\" (using year $year) ... skipping");
      next;
    }
    # Extra check to see that chart week-day matches the one we get for this year
    unless($date->wday == $wday) 
    {
      &error('WARNING! Invalid weekday for "'.&norm($e->as_text()).
	     "\", probably wrong year ($year) ... skipping");
      next;
    }
    # EO Consistency check
    
    $dsh->StartBatch($self->{xmltvid}.'_'.$date->ymd('-'), $channel_id);

    &error("WARNING! Does not recognize document structure trying to get schedule anyway ...\n")
	unless $e->right()->attr('_tag') eq 'p';

    my $first= 0;
    for my $t ($e->right())
    {
      next unless ref($t) eq 'HTML::Element';

      # We're done when we find next day
      last if($t->as_text() =~ 
	      m/^\s*($weekday)\s*[0-9][0-9]?\s*($month)\s*$/i);

      next unless($t->as_text() =~ m/^\s*([0-9]{2})([0-9]{2})\s+/ &&
		  $1 < 24 && $2 < 60); # valid start time?

      (my $h, my $m)= ($1,$2);
      

      unless($first) # Save first entry's time
      { 
	$first= "$h$m";
	$dsh->StartDate($date->ymd('-'));
      }
# frax -- This seem to be handled by the DataStore::Helper
#     elsif(int("$h$m") < $first) 
#     { # next day
#	$first= "$h$m";
#	$date->add(days => 1);
#	$dsh->StartDate($date->ymd('-'));
#     }

      my $title= my $descr= '';

      # If we are lucky the title is in bold face and would be easy to find
      if(defined($b= $t->look_down('_tag', 'b')))
      { 
	# Grab first (if any) bold entry withing this programme
	$title= $b->as_text();
	$title=~ s/([()])/\\$1/sg; # escape '(' and ')' for regexp use
      }
      if(length($title) && $t->as_text() =~ m/^\s*$h$m\s$title\s*(.*)/s) 
      {
	# The found bold text is first after the start time,
	# so we consider it to be the title
	$descr= $1;
      }
      else 
      {
	# Let's Check for Upper-Case title instead
	if($t->as_text() =~ m/\s*[0-9]{4}\s+((([A-Z0-9\'\"\&.,!?<>{}()\[\];:_-]+|([0-9]+\'?[sS]))+\s+)+)(.*)/s) 
	{
	  $title= $1;
	  $descr= $5;
	  if($descr =~ m/^[a-z&]/) 
	  {
	    # if the next word after the title starts with
	    # lowercase or is an '&' we probably got one word to much
	    $title=~ s/([^\s]+)\s*$//;
	    $descr= "$1 $descr";
	  }
	} 
	else 
	{
	  &error('WARNING! Did not find title in the following entry: "'. 
		 &norm($e->as_text())."\" at $h:$m\n");
	  $title= 'UNKNOWN';
	  ($descr= $t->as_text()) =~ s/^\s*[0-9]{4}\s+//;
	}
      }
      $title=~ s/\\([()])/$1/sg; # remove ()-esc
      my $ce = 
      { 
	title       => &norm($title),
	start_time  => "$h:$m",
      };
      $ce->{'description'}= &norm($descr)
	  unless $descr =~ m/^\s*$/;
      $dsh->AddProgramme($ce);
    }
    if($first) 
    {
      $dsh->EndBatch(1);
    }
    else 
    {
      &error('WARNING! No programmes found for "'.&norm($e->as_text()).'"');
      $dsh->EndBatch(0, 'Did not find any programmes');
    }
  }
}

sub norm
{
  return '' unless defined $_[0];
  my $str = Utf8Conv($_[0]);

  $str =~ tr/\n\r\t\xa0 /    /s; # a0 is nonbreaking space.
  
  $str =~ s/^\s+//;
  $str =~ s/\s+$//;
  
  return $str;
}

1;
