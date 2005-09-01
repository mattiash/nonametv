# $Id: Nickelodeon.pm,v 1.18 2005/09/01 16:18:04 frax Exp $
#package NonameTV::Importer::Nickelodeon;
# The above should probably be the final package name after Mattias have finished it.
# For now we use this:
package Nickelodeon;

use strict;
use warnings;

use DateTime;
use DateTime::Duration;

use Unicode::String qw/utf8/;

# The subroutine "*2HTMLTree" should probably be in NonameTV.pm
# If we should continue to use it 
# (Mattis might want to use XMLLib instead of the HTML libs)
# I have also implemented a fake DataStore::Helper object 
# use NonameTV 
use frax qw(&WordFile2HTMLTree &HTMLFile2HTMLTree &DataStoreHelper_new &Utf8Conv);

# These should probably be used in Mattias final version
#use NonameTV::DataStore::Helper;
#use NonameTV::Importer;
#use base 'NonameTV::Importer';

use HTML::TreeBuilder;
use HTML::Entities; 


# Since I don't have access to the NonameTV::Importer module which
# this probably should be inherited from, we do just a simple
# constructor
sub new 
{
    my $this= shift;
    my $class= ref($this) || $this;
    my $self= {};
    bless $self, $class;
  
    my $dsh= &DataStoreHelper_new(); 
             #NonameTV::DataStore::Helper->new( $self->{datastore} );
    $self->{datastorehelper} = $dsh;

    return $self;
}

sub Import
{
    my $self = shift;
    my( $p ) = @_;
    
    foreach my $file (@ARGV) {
	print  "Nickelodeon: Processing $file\n";
	$self->ImportFile( "", $file, $p );
    }
}

sub ImportFile
{
    my $self= shift;
    my ($contentname, $file, $p)= @_;

    my $xmltvid= "nickelodeon.se";

    my $channel_id= 'cid';
    # Should probably be as below
    # my $channel_id= $self->{channel_data}->{$xmltvid}->{id};
  
    my $dsh= $self->{datastorehelper};
  
    my $tree;
    if($file =~  m/\.doc$/i) {
	$tree= &WordFile2HTMLTree($file);
    }
    elsif($file =~ /\.html$/) {
	$tree= &HTMLFile2HTMLTree($file);
    }
    else {
	print "Nickelodeon: Unknown extension \"$file\"\n";
    }
  
    if(!defined $tree) {
	print STDERR "Nickelodeon: \"$file\" failed to parse\n";
	return;
    }

    # Some statics used more then once
    my $vard='VARDAGAR|HVERDAG|HVERDAGAR|WEEKDAYS';
    my $helg='HELGER|WEEKENDS';
    my %monthno= ( januari => 1, januar => 1, january => 1, 
		   februari => 2, februar => 2, february => 2,
		   mars => 3, marts => 3, march => 3, 
		   april => 4, 
		   maj => 5, mai => 5, may => 5, 
		   juni => 6, june => 6, 
		   july => 7, juli => 7, 
		   augusti => 8 , august => 8, 
		   september => 9 , 
		   oktober => 10, october => 10, 
		   november => 11, november => 11, 
		   december => 12, desember => 12, );
    my $month= join '|', keys %monthno;
    my $oneday= DateTime::Duration->new(days => 1);

    # Lets find those schedules
    for my $e ($tree->look_down('_tag', 'p',
				sub { 
				    $_[0]->as_text() =~ 
					m/^\s*($vard|$helg)\s*([0-9][0-9]?)(\s*($month))?(\s*2[0-9]{3})?\s*-\s*([0-9][0-9]?)\s*($month)\s*(2[0-9]{3})\s*$/i
				    }
				)
	       ) {
	my $startday= my $endday= undef;
	#print $e->as_text(),"\n";
	if($e->as_text() =~ m/([0-9][0-9]?)\s*($month)\s*(2[0-9]{3})\s*-\s*([0-9][0-9]?)\s*($month)\s*(2[0-9]{3})/i) {
	    # DD Month YYYY - DD Month YYYY (havn't seen this but guess it would be possible)
	    eval { $startday= DateTime->new(year   => $3,
					    month  => $monthno{lc($2)},
					    day    => $1,
					    time_zone => 'Europe/Stockholm'); 
		   $endday= DateTime->new(year   => $6,
					  month  => $monthno{lc($5)},
					  day    => $4,
					  time_zone => 'Europe/Stockholm'); }
	} elsif($e->as_text() =~ m/([0-9][0-9]?)\s*($month)\s*-\s*([0-9][0-9]?)\s*($month)\s*(2[0-9]{3})/i) {
	    # DD Month - DD Month YYYY
	    eval { $startday= DateTime->new(year   => $5,
					    month  => $monthno{lc($2)},
					    day    => $1,
					    time_zone => 'Europe/Stockholm');
		   $endday= DateTime->new(year   => $5,
					  month  => $monthno{lc($4)},
					  day    => $3,
					  time_zone => 'Europe/Stockholm'); }
	} elsif($e->as_text() =~ m/([0-9][0-9]?)\s*-\s*([0-9][0-9]?)\s*($month)\s*(2[0-9]{3})/i) {
	    # DD - DD Month YYYY
	    eval { $startday= DateTime->new(year   => $4,
					    month  => $monthno{lc($3)},
					    day    => $1,
					    time_zone => 'Europe/Stockholm');
		   $endday= DateTime->new(year   => $4,
					  month  => $monthno{lc($3)},
					  day    => $2,
					  time_zone => 'Europe/Stockholm'); }
	} else {
	    die "This should only happen if the regexps above are wrong!";
	}
	unless(defined($startday) && defined($endday)) {
	    print('WARNING! Invalid date in time period: "',&norm($e->as_text()),
		  "\" ... skipping!\n");
	    next;
	}
	#print $startday->ymd,' => ',$endday->ymd,"\n";
	if($startday->compare($endday) > 0) {
	    print("WARNING! Start day (",$startday->ymd('-'),") is after End day (", 
		  $endday->ymd('-'), "), I'm swapping them!\n");
	    my $tmp= $startday;
	    $startday= $endday;
	    $endday= $tmp;
	}
	print "WARNING! Does not recognize document structure trying to get schedule anyway ...\n"
	    unless $e->right()->attr('_tag') eq 'p';
	

	my %sched= ();
	my $title= my $time= undef;
	my $descr= '';
	for my $t ($e->right()) {
	    next unless ref($t) eq 'HTML::Element';
	    if($t->as_text() =~ m/^\s*([0-9]{2}):([0-9]{2})\s+(.*)\s*$/ &&
	       $1 < 24 && $2 < 60) {
		if(defined $time) { # store previous entry when we find new start time
		    print "WARNING! Overwriting exisiting entry (starttime=$time)!\n"
			if exists $sched{$time};
		    $sched{$time}{'title'}= $title;
		    $sched{$time}{'descr'}= $descr if length $descr;
		    #print "$time -- $title -- $descr\n\n";
		    $descr= '';
		}
		$time= "$1:$2";
		$title= &norm($3);
		if($title =~ m/^End|Slut$/) {
		    $title= 'End';
		    $sched{$time}{'title'}= 'end-of-transmission';
		    last;
		}
	    } else {
		my $txt= &norm($t->as_text());
		if(lc($txt) eq 'end' && defined $time) { # Danish schedule have end-tag without time
		    print "WARNING! Overwriting exisiting entry (starttime=$time)!\n"
			if exists $sched{$time};
		    $sched{$time}{'title'}= $title;
		    $sched{$time}{'descr'}= $descr if length $descr;
		    $title= 'End';
		    # We assume last program is 30 minutes long
		    (my $h, my $m)= split /:/, $time;
		    $m+= 30;
		    if($m >= 60) {
			++$h;
			$m-= 60;
		    }
		    $time= sprintf("%02d:%02d", $h, $m);
		    print "WARNING! End of transmission time not found using: $time\n";
		    $sched{"$time"}{'title'}= 'end-of-transmission';
		    last;
		}
		$descr.= (length($descr) ? ' ' : '').$txt;
	    }
	}
	unless(scalar(keys %sched)) {
	    print "WARNING! Schedule not found ... skipping!\n";
	    next;
	}
	print "WARNING! End of transmission not found!\n" unless $title eq 'End';

	# Got entire schedule and days, lets Import it!
	my $weekdays= $e->as_text() =~ m/$vard/ ? '[1-5]' : '[67]';
	while($startday->compare($endday) <= 0) {
	    next if $startday->wday() !~ m/^$weekdays$/;
	    $dsh->StartBatch(${xmltvid}.'_'.$startday->ymd('-'), $channel_id);
	    $dsh->StartDate($startday->ymd('-'));
	    for $time (sort keys(%sched)) {
		my $ce = { 
		    title       => $sched{$time}{'title'},
		    start_time  => $time
		};
		$ce->{'descr'}= $sched{$time}{'descr'} if exists $sched{$time}{'descr'};
		$dsh->AddProgramme($ce);
	    }
	} continue {
	    $startday->add_duration($oneday);
	}
	$dsh->EndBatch(1);
   }
}

sub norm
{
    return '' unless defined $_[0];

    my $str = Utf8Conv(&utf8($_[0])->latin1);

    $str =~ tr/\n\r\t\xa0 /    /s; # a0 is nonbreaking space.

    $str =~ s/^\s+//;
    $str =~ s/\s+$//;
    
    return $str;
}

1;
