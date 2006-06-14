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
use Text::Capitalize qw/capitalize_title/;

use NonameTV qw/Wordfile2HtmlTree Htmlfile2HtmlTree norm/;
use NonameTV::DataStore::FilePrint;
use NonameTV::DataStore::Helper;

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
  
  my $dsh=  NonameTV::DataStore::Helper->new( $self->{datastore},
                                              'Europe/Stockholm');
  $self->{datastorehelper} = $dsh;

  # Set the below to an interger in the range 2000 - 2999 to
  # override automatic year detection.
  $self->{year} = undef;

  my $sth = $self->{datastore}->Iterate( 'channels', 
                                         { grabber => 'vh1' },
                                         qw/xmltvid id grabber_info/ )
    or logdie("Failed to fetch grabber data");
  
  while( my $data = $sth->fetchrow_hashref )
  {
    $self->{channel_data}->{$data->{xmltvid}} = 
    { id => $data->{id}, };
  }
  $sth->finish;

  $self->{OptionSpec} = [ qw/verbose/ ];
  $self->{OptionDefaults} = { 
    'verbose' => 0,
  };
  
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

  $self->{xmltvid}="vh1.com";

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

  # Misspelled month-names.
  $monthno{febuary} = 2;

  my $month= join '|', keys %monthno;
  my %weekdayno= ( monday => 1, tuesday => 2, wednesday => 3, thursday => 4,
		   friday => 5, saturday => 6, sunday => 7 ); 
  my $weekday= join '|', keys %weekdayno;

  # Lets find those schedules
  for my $e ($tree->look_down('_tag', 'p', sub { $_[0]->as_text() =~ m/^\s*($weekday)\s*[0-9][0-9]?\s*($month)\s*$/i }) ) 
  {
    $e->as_text() =~ m/^\s*($weekday)\s*([0-9][0-9]?)\s*($month)\s*$/i
	or &logdie("Mismatched heading: " . $e->as_text() );
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
      &error("$file: Invalid date '" . &norm($e->as_text()) .
	     "' (using year $year) ... skipping" );
      next;
    }
    # Extra check to see that chart week-day 
    # matches the one we get for this year
    unless($date->wday == $wday) 
    {
      &error("$file: Invalid weekday for '" . &norm($e->as_text()) .
	     "', probably wrong year ($year) ... skipping");
      next;
    }
    # EO Consistency check
    
    $dsh->StartBatch($self->{xmltvid}.'_'.$date->ymd('-'), $channel_id);

    &error("$file: Does not recognize document structure trying to get schedule anyway ...\n")
	unless $e->right()->attr('_tag') eq 'p';

    my $first= undef;
    for my $t ($e->right())
    {
      next unless ref($t) eq 'HTML::Element';

      # We're done when we find next day
      last if($t->as_text() =~ 
	      m/^\s*($weekday)\s*[0-9][0-9]?\s*($month)\s*$/i);

      next unless($t->as_text() =~ m/^\s*([0-9]{2})([0-9]{2})\s+/ &&
		  $1 < 24 && $2 < 60); # valid start time?

      (my $h, my $m)= ($1,$2);
      

      unless(defined $first) # Save first entry's time
      { 
	$first= "$h$m";
	$dsh->StartDate($date->ymd('-'));
      }

      my $title = '';
      my $descr= '';

      my $entry = $t->as_text();
      $entry =~ s/^\s+//;
      $entry =~ tr/ / /s;

      my( undef, $entrytext ) = ($entry =~ /^\s*([0-9]{4})\s+(.*)/);

      # If we are lucky the title is in bold face and would be easy to find
      if(defined(my $b= $t->look_down('_tag', 'b')))
      { 
	# Grab first (if any) bold entry withing this programme
	$title= $b->as_text();
        $title =~ s/^\s+//;
        $title =~ tr/ / /s;
      }

      # The title is always in upper-case and is followed by the
      # description in Mixed Case.
      if($entry =~ m/\s*[0-9]{4}\s+([A-Z0-9\'\&s\/ \-:]+)\s+([A-Z].*)/)
      {
        $title= $1;
        $descr= $2;
      } 
      else 
      {
        &error("$file: Did not find title in the following entry: '" . 
               &norm($entry) . "' at $h:$m");
        $title= 'UNKNOWN';
        $descr= $entrytext;
      }

      $title=~ s/\\([()])/$1/sg; # remove ()-esc
      $title = capitalize_title( &norm($title) );
      $title =~ s/Vh1/VH1/g;

      my $ce = 
      { 
	title       => $title,
	start_time  => "$h:$m",
      };
      $ce->{'description'}= &norm($descr)
	  unless $descr =~ m/^\s*$/;
      $dsh->AddProgramme($ce);
    }
    if(defined $first) 
    {
      $dsh->EndBatch(1);
    }
    else 
    {
      &error("$file: No programmes found for '" . &norm($e->as_text()) ."'" );
      $dsh->EndBatch(0, 'Did not find any programmes');
    }
  }
}

1;
