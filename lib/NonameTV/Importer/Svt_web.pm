package NonameTV::Importer::Svt_web;

=pod

This importer imports data from SvT's press site. The data is fetched
as one html-file per day and channel.

Features:

Episode-info parsed from description.

=cut

use strict;
use warnings;

use DateTime;
use XML::LibXML;
use DateTime;

use NonameTV qw/MyGet norm Html2Xml ParseDescCatSwe AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/info progress error logdie/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

my @SVT_CATEGORIES = qw(Barn Sport Unclassified
                        Musik/Dans Samhälle Fritid
                        Kultur Drama Nyheter 
                        Nöje Film Fakta);

# my @SVT_CATEGORIES = ("");

my %channelids = ( "SVT1" => "svt1.svt.se",
                   "SVT2" => "svt2.svt.se",
                   );

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{grabber_name} = "Svt";

    defined( $self->{Username} ) or die "You must specify Username";
    defined( $self->{Password} ) or die "You must specify Password";

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $self->{datastorehelper} = $dsh;

    # We need to login to the site before we can do anything else.
    # The login is stored as a cookie behind the scenes by LWP.
    my( $d1, $d2 ) =  $self->Login();

    return $self;
}

sub ImportContent
{
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};
  $self->{currxmltvid} = $chd->{xmltvid};

  my( $date ) = ($batch_id =~ /_(.*)$/);

  {
    my( $year, $month, $day ) = split("-", $date);
    $self->{currdate} = DateTime->new( year => $year,
                                       month => $month, 
                                       day => $day );
  }

  my $cat = $self->FetchCategories( $chd, $date );

  my $doc = Html2Xml( $$cref );
  
  if( not defined( $doc ) )
  {
    error( "$batch_id: Failed to parse." );
    return 0;
  }

  # Check that we have downloaded data for the correct day.
  my $daytext = $doc->findvalue( '//font[@class="header"]' );
  my( $day ) = ($daytext =~ /\b(\d{1,2})\D+(\d{4})\b/);

  if( not defined( $day ) )
  {
    error( "$batch_id: Failed to find date in page ($daytext)" );
    return 0;
  }

  my( $dateday ) = ($date =~ /(\d\d)$/);

  if( $day != $dateday )
  {
    error( "$batch_id: Wrong day: $daytext" );
    return 0;
  }
        
  # The data really looks like this...
  my $ns = $doc->find( "//table/td/table/tr/td/table/tr" );
  if( $ns->size() == 0 )
  {
    error( "$batch_id: No data found" );
    return 0;
  }

  $dsh->StartDate( $date, "03:00" );
  
  my $skipfirst = 1;
  my $programs = 0;

  foreach my $pgm ($ns->get_nodelist)
  {
    if( $skipfirst )
    {
      $skipfirst = 0;
      next;
    }
    
    my $time  = $pgm->findvalue( 'td[1]//text()' );
    my $title = $pgm->findvalue( 'td[2]//font[@class="text"]//text()' );
    my $desc  = $pgm->findvalue( 'td[2]//font[@class="textshorttabla"]//text()' );
    
    my( $starttime ) = ( $time =~ /^\s*(\d+\.\d+)/ );
    my( $endtime ) = ( $time =~ /-\s*(\d+.\d+)/ );
    
    $starttime =~ tr/\./:/;
    if( $starttime !~ /\d+:\d+/ )
    {
      next;
    }
    
    my $ce =  {
      start_time  => $starttime,
      title       => norm_title($title),
      description => norm_desc($desc),
      svt_cat     => $cat->{$title},
    };
    
    if( defined( $endtime ) )
    {
      $endtime =~ tr/\./:/;
      $ce->{end_time} = $endtime;
    }
    
    $self->extract_extra_info( $ce );
    $dsh->AddProgramme( $ce );
    $programs++;
  }
  
  if( $programs > 0 )
  {
    # Success
    return 1;
  }
  else
  {
    # This is normal for some channels. We do not want to rollback
    # because of this.
    error( "$batch_id: No programs found" )
      if( not $chd->{empty_ok} );
    return 1;
  }
}

# Fetch the association between title and category/program_type for a
# specific channel and day. This is done by fetching the listings for each
# category during the day and looking at which titles are returned.
sub FetchCategories
{
  my $self = shift;
  my( $chd, $date ) = @_;

  my $ds = $self->{datastore};

  my $cat = {};

  foreach my $svt_cat (@SVT_CATEGORIES)
  {
#    my( $program_type, $category ) = $ds->LookupCat( "Svt", $svt_cat );
    my $batch_id = $chd->{xmltvid} . "_" . $svt_cat . "_" . $date;
    info( "$batch_id: Fetching categories" );
    
    my( $content, $code ) = $self->FetchData( $batch_id, $chd );

    my $doc = Html2Xml( $content );
  
    if( not defined( $doc ) )
    {
      error( "$batch_id: Failed to parse." );
      next;
    }
  
    # The data really looks like this...
    my $ns = $doc->find( "//table/td/table/tr/td/table/tr" );
    if( $ns->size() == 0 )
    {
#      error( "$batch_id: No data found" );
      next;
    }
  
    my $skipfirst = 1;
    foreach my $pgm ($ns->get_nodelist)
    {
      if( $skipfirst )
      {
        $skipfirst = 0;
        next;
      }
    
      my $title = $pgm->findvalue( 'td[2]//font[@class="text"]//text()' );
      $cat->{$title} = $svt_cat;
    }
  }    
  return $cat;
}

sub Login
{
  my $self = shift;

  my $username = $self->{Username};
  my $password = $self->{Password};

  my $url = "http://www.pressinfo.svt.se/app/index.asp?"
    . "SysLoginName=$username"
    . "\&SysPassword=$password";

  # Do the login. This will set a cookie that will be transferred on all
  # subsequent page-requests.
  MyGet( $url );
  
  # We should probably do some error-checking here...
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  # http://www.pressinfo.svt.se/app/schedule_full.html.dl?kanal=SVT%201&Sched_day_from=0&Sched_day_to=0&Det=Det&Genre=&Freetext=
  # Day=0 today, Day=1 tomorrow etc. Day can be negative.
  # kanal SVT 1, SVT 2, SVT Europa, Barnkanalen, 24, Kunskapskanalen

  my( $svt_cat, $date ) = ($batch_id =~ /_(.*)_(.*)/);
  if( not defined( $svt_cat ) )
  {
    $svt_cat = "",
    ($date) = ($batch_id =~ /_(.*)/);
  }

  my( $year, $month, $day ) = split( '-', $date );
  my $dt = DateTime->new( 
                          year  => $year,
                          month => $month,
                          day   => $day 
                          );

  my $today = DateTime->today( time_zone=>'local' );
  my $day_diff = $dt->subtract_datetime( $today )->delta_days;

  my $u = URI->new('http://www.pressinfo.svt.se/app/schedule_full.html.dl');
  $u->query_form( {
    kanal => $data->{grabber_info},
    Sched_day_from => $day_diff,
    Sched_day_to => $day_diff,
    Det => "Det",
    Genre => $svt_cat,
    Freetext => ""});

  my( $content, $code ) = MyGet( $u->as_string );
  return( $content, $code );
}

sub extract_extra_info
{
  my $self = shift;
  my( $ce ) = shift;

  my( $ds ) = $self->{datastore};

  extract_episode( $ce );

  my( $program_type, $category );

  if( defined( $ce->{svt_cat} ) )
  {
    ($program_type, $category ) = $ds->LookupCat( "Svt", 
                                                  $ce->{svt_cat} );
    AddCategory( $ce, $program_type, $category );
  }

  #
  # Try to extract category and program_type by matching strings
  # in the description. The empty entry is to make sure that there
  # is always at least one entry in @sentences.
  #

  my @sentences = (split_text( $ce->{description} ), "");
  
  ( $program_type, $category ) = ParseDescCatSwe( $sentences[0] );

  # If this is a movie we already know it from the svt_cat.
  if( defined($program_type) and ($program_type eq "movie") )
  {
    $program_type = undef; 
  }

  AddCategory( $ce, $program_type, $category );

  if( defined( $ce->{svt_cat} ) )
  {
    ($program_type, $category ) = $ds->LookupCat( "Svt_fallback", 
                                                  $ce->{svt_cat} );
    AddCategory( $ce, $program_type, $category );
  }

  # Find production year from description.
  if( $sentences[0] =~ /\bfr.n (\d\d\d\d)\b/ )
  {
    $ce->{production_date} = "$1-01-01";
  }

  $ce->{title} =~ s/^Seriestart:\s*//;
  $ce->{title} =~ s/^Novellfilm:\s*//;

  # Default aspect is 4:3.
  $ce->{aspect} = "4:3";

  for( my $i=0; $i<scalar(@sentences); $i++ )
  {
    if( $sentences[$i] eq "Bredbild." )
    {
      $ce->{aspect} = "16:9";
      $sentences[$i] = "";
    }
    elsif( my( $directors ) = ($sentences[$i] =~ /^Regi:\s*(.*)/) )
    {
      $ce->{directors} = parse_person_list( $directors );
      $sentences[$i] = "";
    }
    elsif( my( $actors ) = ($sentences[$i] =~ /^I rollerna:\s*(.*)/ ) )
    {
      $ce->{actors} = parse_person_list( $actors );
      $sentences[$i] = "";
    }
    elsif( $sentences[$i] =~ /^(Även|Från)
     ((
      \s+|
      [A-Z]\S+|
      i\s+[A-Z]\S+|
      tidigare\s+i\s*dag|senare\s+i\s*dag|
      tidigare\s+i\s*kväll|senare\s+i\s*kväll|
      \d+\/\d+|
      ,|och|samt
     ))+
     \.\s*
     $/x )
    {
      $self->parse_other_showings( $ce, $sentences[$i] );

#      print STDERR $sentences[$i] . "\n";
#      $sentences[$i] = "";
    }
    elsif( $sentences[$i] =~ /^Text(at|-tv)\s+sid(an)*\s+\d+\.$/ )
    {
#      $ce->{subtitle} = 'sv,teletext';
#      $sentences[$i] = "";
    }
  }
  
  $ce->{description} = join_text( @sentences );

  # Remove temporary fields
  delete( $ce->{svt_cat} );
}

sub parse_person_list
{
  my( $str ) = @_;

  # Remove all variants of m.fl.
  $str =~ s/\s*m[\. ]*fl\.*\b//;
  
  # Remove trailing '.'
  $str =~ s/\.$//;

  $str =~ s/\boch\b/,/;
  $str =~ s/\bsamt\b/,/;

  my @persons = split( /\s*,\s*/, $str );
  foreach (@persons)
  {
    # The character name is sometimes given . Remove it.
    # The Cast-entry is sometimes cutoff, which means that the
    # character name might be missing a trailing ).
    s/\s*\(.*$//;
    s/.*\s+-\s+//;
  }

  return join( ", ", grep( /\S/, @persons ) );
}

sub extract_episode
{
  my( $ce ) = @_;

  return if not defined( $ce->{description} );

  my $d = $ce->{description};

  # Try to extract episode-information from the description.
  my( $ep, $eps );
  my $episode;

  my $dummy;

  # Del 2
  ( $dummy, $ep ) = ($d =~ /\b(Del|Avsnitt)\s+(\d+)/ );
  $episode = sprintf( " . %d .", $ep-1 ) if defined $ep;

  # Del 2 av 3
  ( $dummy, $ep, $eps ) = ($d =~ /\b(Del|Avsnitt)\s+(\d+)\s*av\s*(\d+)/ );
  $episode = sprintf( " . %d/%d . ", $ep-1, $eps ) 
    if defined $eps;
  
  $ce->{episode} = $episode if defined $episode;
}

sub parse_other_showings
{
  my $self = shift;
  my( $ce, $l ) = @_;

  my $type;
  my $channel = "same";
  my $date = "unknown";

 PARSER: 
  {
    if( $l =~ /\G(Även|Från)\s*/gcx ) 
    {
      $type = ($1 eq "Även") ? "also" : "previously";
      
      redo PARSER;
    }
    if( $l =~ /\Gi*\s* ([A-Z]\w*) \s*/gcx ) 
    {
      $channel = $1;
      redo PARSER;
    }
    if( $l=~ /\G(tidigare\s+i\s*dag
                 |senare\s+i\s*dag
                 |tidigare\s+i\s*kväll
                 |senare\s+i\s*kväll)\s*/gcx )  
    {
      $date = "today";
      redo PARSER;
    }
    if( $l =~ /\G(\d+\/\d+)\s*/gcx )
    {
      $date = $1;
      redo PARSER;
    }
    if( $l =~ /\G(,|och|samt)\s*/gcx ) 
    {
      $self->add_showing( $ce, $type, $date, $channel );
      $date = "unknown";
      $channel = "same";
      redo PARSER;
    }
    if( $l =~ /\G(\.)\s*/gcx ) 
    {
      $self->add_showing( $ce, $type, $date, $channel );
      $date = "unknown";
      $channel = "same";
      redo PARSER;
    }
    if( $l =~ /\G(.+)/gcx ) 
    {
      print "error: $1\n";
      redo PARSER;
    }
    
  }
}
    
sub add_showing
{
  my $self = shift;
  my( $ce, $type, $date, $channel ) = @_;

  my $chid;

  # Ignore entries caused by ", och"
  return if $date eq "unknown" and $channel eq "same";

  if( $channel eq "same" )
  {
    $chid = $self->{currxmltvid};
  }
  else
  {
    $chid = $channelids{$channel};
  }

  my $dt = DateTime->today();
  
  if( $date ne "today" )
  {
    my( $day, $month ) = ($date =~ /(\d+)\s*\/\s*(\d+)/);
    if( not defined( $month ) )
    {
      error( "Unknown date $date" );
      return;
    }
    $dt->set( month => $month,
              day => $day );

    if( $dt > $self->{currdate} )
    {
      if( $type eq "previously" )
      {
        $dt->subtract( years => 1 );
      }
    }
    else
    {
      if( $type eq "also" )
      {
        $dt->add( years => 1 );
      }
    }
  }

  $date = $dt->ymd("-");

  error( "Unknown channel $channel" )
    unless defined $chid;

#  print STDERR "$type $date $chid\n";
}

# Split a string into individual sentences.
sub split_text
{
  my( $t ) = @_;

  return () if not defined( $t );

  # Remove any trailing whitespace
  $t =~ s/\s*$//;

  # Replace strange dots.
  $t =~ tr/\x2e/./;

  # We might have introduced some errors above. Fix them.
  $t =~ s/([\?\!])\./$1/g;

  # Replace ... with ::.
  $t =~ s/\.{3,}/::./g;

  # Lines ending with a comma is not the end of a sentence
#  $t =~ s/,\s*\n+\s*/, /g;

# newlines have already been removed by norm() 
  # Replace newlines followed by a capital with space and make sure that there 
  # is a dot to mark the end of the sentence. 
#  $t =~ s/([\!\?])\s*\n+\s*([A-ZÅÄÖ])/$1 $2/g;
#  $t =~ s/\.*\s*\n+\s*([A-ZÅÄÖ])/. $1/g;

  # Turn all whitespace into pure spaces and compress multiple whitespace 
  # to a single.
  $t =~ tr/\n\r\t \xa0/     /s;

  # Mark sentences ending with '.', '!', or '?' for split, but preserve the 
  # ".!?".
  $t =~ s/([\.\!\?])\s+([A-ZÅÄÖ])/$1;;$2/g;
  
  my @sent = grep( /\S\S/, split( ";;", $t ) );

  if( scalar( @sent ) > 0 )
  {
    # Make sure that the last sentence ends in a proper way.
    $sent[-1] =~ s/\s+$//;
    $sent[-1] .= "." 
      unless $sent[-1] =~ /[\.\!\?]$/;
  }

  return @sent;
}

# Join a number of sentences into a single paragraph.
# Performs the inverse of split_text
sub join_text
{
  my $t = join( " ", grep( /\S/, @_ ) );
  $t =~ s/::/../g;

  return $t;
}

sub norm_desc
{
  my( $str ) = @_;

  # Replace strange bullets with end-of-sentence.
  $str =~ s/([\.!?])\s*\x{95}\s*/$1 /g;
  $str =~ s/\s*\x{95}\s*/. /g;

  return norm( $str );
}

sub norm_title
{
  my( $str ) = @_;

  # Remove strange bullets.
  $str =~ s/\x{95}/ /g;

  return norm( $str );
}


1;
