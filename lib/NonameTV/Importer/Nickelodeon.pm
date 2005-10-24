package NonameTV::Importer::Nickelodeon;

use strict;
use warnings;

=pod

Import data from Word-files delivered via e-mail. 

Features:

=cut

use DateTime;
use DateTime::Duration;

use HTML::TreeBuilder;
use HTML::Entities; 

use NonameTV qw/MyGet Wordfile2HtmlTree Htmlfile2HtmlTree Utf8Conv/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/info progress error logdie/;

use NonameTV::Importer;

use base 'NonameTV::Importer';

sub new 
{
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);
  
  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  my $sth = $self->{datastore}->Iterate( 'channels', 
                                         { grabber => 'nickelodeon' },
                                         qw/xmltvid id grabber_info/ )
    or logdie "Failed to fetch grabber data";

  while( my $data = $sth->fetchrow_hashref )
  {
    $self->{channel_data}->{$data->{xmltvid}} = 
                            { id => $data->{id}, };
  }

  $sth->finish;

  $self->{OptionSpec} = [ qw/verbose/ ];
  $self->{OptionDefaults} = { 
    'verbose'      => 0,
  };

  return $self;
}

sub Import
{
  my $self = shift;
  my( $p ) = @_;

  foreach my $file (@ARGV)
  {
    progress( "Nickelodeon: Processing $file" );
    $self->ImportFile( "", $file, $p );
  } 
}

sub ImportFile
{
  my $self= shift;
  my ($contentname, $file, $p)= @_;
  
  my $xmltvid= "nickelodeon.se";
  
  my $channel_id= $self->{channel_data}->{$xmltvid}->{id};
  
  my $dsh= $self->{datastorehelper};
  
  my $tree;
  if($file =~  m/\.doc$/i) {
    $tree= &Wordfile2HtmlTree($file);
  }
  elsif($file =~ /\.html$/) {
    $tree= &Htmlfile2HtmlTree($file);
  }
  else {
    error( "Nickelodeon: Unknown extension \"$file\"" );
    return 0;
  }
  
  if(!defined $tree) {
    error( "Nickelodeon: \"$file\" failed to parse" );
    return 0;
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
       } ) ) 
  {
    my $startday= my $endday= undef;
    #print $e->as_text(),"\n";
    if($e->as_text() =~ m/([0-9][0-9]?)\s*($month)\s*(2[0-9]{3})\s*-\s*([0-9][0-9]?)\s*($month)\s*(2[0-9]{3})/i) 
    {
      # DD Month YYYY - DD Month YYYY 
      # (haven't seen this but guess it would be possible)
      eval 
      { 
        $startday = DateTime->new( year   => $3,
                                   month  => $monthno{lc($2)},
                                   day    => $1,
                                   time_zone => 'Europe/Stockholm'); 

        $endday= DateTime->new(year   => $6,
                               month  => $monthno{lc($5)},
                               day    => $4,
                               time_zone => 'Europe/Stockholm'); 
      }
    } 
    elsif($e->as_text() =~ m/([0-9][0-9]?)\s*($month)\s*-\s*([0-9][0-9]?)\s*($month)\s*(2[0-9]{3})/i) 
    {
      # DD Month - DD Month YYYY
      eval 
      { 
        $startday= DateTime->new(year   => $5,
                                 month  => $monthno{lc($2)},
                                 day    => $1,
                                 time_zone => 'Europe/Stockholm');
        
        $endday= DateTime->new(year   => $5,
                               month  => $monthno{lc($4)},
                               day    => $3,
                               time_zone => 'Europe/Stockholm'); 
      }
    } 
    elsif($e->as_text() =~ m/([0-9][0-9]?)\s*-\s*([0-9][0-9]?)\s*($month)\s*(2[0-9]{3})/i) 
    {
      # DD - DD Month YYYY
      eval 
      { 
        $startday= DateTime->new(year   => $4,
                                 month  => $monthno{lc($3)},
                                 day    => $1,
                                 time_zone => 'Europe/Stockholm');

        $endday= DateTime->new(year   => $4,
                               month  => $monthno{lc($3)},
                               day    => $2,
                               time_zone => 'Europe/Stockholm'); 
      }
    } 
    else 
    {
      logdie "This should only happen if the regexps above are wrong!";
    }
    
    unless(defined($startday) && defined($endday)) 
    {
      error('$file: WARNING! Invalid date in time period: "' .
            &norm($e->as_text()) . "\" ... skipping!");
      next;
    }

    #print $startday->ymd,' => ',$endday->ymd,"\n";
    if($startday->compare($endday) > 0) 
    {
      error("$file: Start day (" . $startday->ymd('-') . 
            ") is after End day (" . $endday->ymd('-') .
            "), I'm adding a year to End day!");
      $endday = $endday->add( years => 1 );
    }

    error( "$file: Does not recognize document structure. " . 
           "Trying to get schedule anyway ..." )
      unless $e->right()->attr('_tag') eq 'p';

    my %sched= ();
    my $title= my $time= undef;
    my $descr= '';
    for my $t ($e->right()) 
    {
      next unless ref($t) eq 'HTML::Element';
      if($t->as_text() =~ m/^\s*([0-9]{2}):([0-9]{2})\s+(.*)\s*$/ &&
         $1 < 24 && $2 < 60) {
        if(defined $time) 
        { 
          # store previous entry when we find new start time
          error( "$file: Overwriting exisiting entry (starttime=$time)!" )
            if exists $sched{$time};

          $sched{$time}{'title'}= $title;
          $sched{$time}{'descr'}= $descr if length $descr;
          #print "$time -- $title -- $descr\n\n";
          $descr= '';
        }

        $time= "$1:$2";
        $title= norm($3);
        if($title =~ m/^End|Slut$/) 
        {
          $title= 'End';
          $sched{$time}{'title'}= 'end-of-transmission';
          last;
        }
      } 
      else 
      {
        my $txt= norm($t->as_text());

        if(lc($txt) eq 'end' && defined $time) 
        { 
          # Danish schedule have end-tag without time
          error( "$file: Overwriting exisiting entry (starttime=$time)!" )
            if exists $sched{$time};

          $sched{$time}{'title'}= $title;
          $sched{$time}{'descr'}= $descr if length $descr;
          $title= 'End';
          # We assume last program is 30 minutes long
          (my $h, my $m)= split /:/, $time;
          $m+= 30;
          if($m >= 60) 
          {
            ++$h;
            $m-= 60;
          }
          $time= sprintf("%02d:%02d", $h, $m);
          error( "$file: End of transmission time not found using: $time" );
          $sched{"$time"}{'title'}= 'end-of-transmission';
          last;
        }

        $descr.= (length($descr) ? ' ' : '').$txt;
      }
    }

    unless(scalar(keys %sched)) 
    {
      error( "$file: Schedule not found ... skipping!" );
      next;
    }

    error( "$file: End of transmission not found!" )
      unless $title eq 'End';

    # Got entire schedule and days, lets Import it!
    my $weekdays= $e->as_text() =~ m/$vard/ ? '[1-5]' : '[67]';
    while($startday->compare($endday) <= 0) 
    {
      next if $startday->wday() !~ m/^$weekdays$/;
      $dsh->StartBatch(${xmltvid}.'_'.$startday->ymd('-'), $channel_id);
      $dsh->StartDate($startday->ymd('-'));
      for $time (sort keys(%sched)) 
      {
        my $ce = 
        { 
          title       => $sched{$time}{'title'},
          start_time  => $time
        };

        $ce->{'description'}= $sched{$time}{'descr'} 
          if exists $sched{$time}{'descr'};

        $dsh->AddProgramme($ce);
      }
      $dsh->EndBatch(1);
    } 
    continue 
    {
      $startday->add_duration($oneday);
    }
  }

  $tree->delete;
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
