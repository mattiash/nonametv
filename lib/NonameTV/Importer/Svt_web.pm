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

use NonameTV qw/MyGet Utf8Conv Html2Xml ParseDescCatSwe AddCategory/;
use NonameTV::DataStore::Helper;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

my @SVT_CATEGORIES = qw(Barn Sport Unclassified
                        Musik/Dans Samhälle Fritid
                        Kultur Drama Nyheter 
                        Nöje Film Fakta);

# my @SVT_CATEGORIES = ("");

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

  my $l = $self->{logger};
  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  my( $date ) = ($batch_id =~ /_(.*)$/);
 
  my $cat = $self->FetchCategories( $chd, $date );

  my $doc = Html2Xml( $$cref );
  
  if( not defined( $doc ) )
  {
    $l->error( "$batch_id: Failed to parse." );
    return;
  }

  # Check that we have downloaded data for the correct day.
  my $daytext = $doc->findvalue( '//font[@class="header"]' );
  my( $day ) = ($daytext =~ /\b(\d{1,2})\D+(\d{4})\b/);
  my( $dateday ) = ($date =~ /(\d\d)$/);

  if( $day != $dateday )
  {
    $l->error( "$batch_id: Wrong day: $daytext" );
    return;
  }
        
  # The data really looks like this...
  my $ns = $doc->find( "//table/td/table/tr/td/table/tr" );
  if( $ns->size() == 0 )
  {
    $l->error( "$batch_id: No data found" );
    return;
  }

  $dsh->StartBatch( $batch_id, $chd->{id} );
  $dsh->StartDate( $date, "03:00" );
  
  my $skipfirst = 1;
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
    
    my $ce =  {
      start_time  => $starttime,
      title       => norm($title),
      description => norm($desc),
      svt_cat     => $cat->{$title},
    };
    
    if( defined( $endtime ) )
    {
      $endtime =~ tr/\./:/;
      $ce->{end_time} = $endtime;
    }
    
    $self->extract_extra_info( $ce );
    $dsh->AddProgramme( $ce );
  }
  
  $dsh->EndBatch( 1 );
}

# Fetch the association between title and category/program_type for a
# specific channel and day. This is done by fetching the listings for each
# category during the day and looking at which titles are returned.
sub FetchCategories
{
  my $self = shift;
  my( $chd, $date ) = @_;

  my $ds = $self->{datastore};
  my $l = $self->{logger};

  my $cat = {};

  foreach my $svt_cat (@SVT_CATEGORIES)
  {
#    my( $program_type, $category ) = $ds->LookupCat( "Svt", $svt_cat );
    my $batch_id = $chd->{xmltvid} . "_" . $svt_cat . "_" . $date;
    $l->info( "$batch_id: Fetching categories" );
    
    my( $content, $code ) = $self->FetchData( $batch_id, $chd );

    my $doc = Html2Xml( $content );
  
    if( not defined( $doc ) )
    {
      $l->error( "$batch_id: Failed to parse." );
      next;
    }
  
    # The data really looks like this...
    my $ns = $doc->find( "//table/td/table/tr/td/table/tr" );
    if( $ns->size() == 0 )
    {
#      $l->error( "$batch_id: No data found" );
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

  my $day_diff = $dt->subtract_datetime( DateTime->today )->delta_days;

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
  # in the description.
  #
  my @sentences = split_text( $ce->{description} );
  
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

  # Find aspect-info and remove it from description.
  if( $ce->{description} =~ s/\bBredbild\b\.*\s*// )
  {
    $ce->{aspect} = "16:9";
  }
  else
  {
    $ce->{aspect} = "4:3";
  }

  # Remove temporary fields
  delete( $ce->{svt_cat} );
}

sub extract_episode
{
  my( $ce ) = @_;

  return if not defined( $ce->{description} );

  my $d = $ce->{description};

  # Try to extract episode-information from the description.
  my( $ep, $eps );
  my $episode;

  # Del 2
  ( $ep ) = ($d =~ /\bDel\s+(\d+)/ );
  $episode = sprintf( " . %d .", $ep-1 ) if defined $ep;

  # Del 2 av 3
  ( $ep, $eps ) = ($d =~ /\bDel\s+(\d+)\s*av\s*(\d+)/ );
  $episode = sprintf( " . %d/%d . ", $ep-1, $eps ) 
    if defined $eps;
  
  $ce->{episode} = $episode if defined $episode;
}

# Split a string into individual sentences.
sub split_text
{
  my( $t ) = @_;

  return $t if $t !~ /\./;

  # Remove any trailing whitespace
  $t =~ s/\s*$//;

  # Replace newlines
  $t =~ s/\n/ . /g;

  # Replace ellipses (...) with &ellip;.
  $t =~ s/\.\.\./&ellip;./;

  my @sent = grep( /\S/, split( /\.\s+/, $t ) );
  map { s/\s+$// } @sent;
  $sent[-1] =~ s/\.\s*$//;

  return @sent;
}

# Join a number of sentences into a single paragraph.
# Performs the inverse of split_text
sub join_text
{
  my $t = join( ". ", grep( /\S/, @_ ) );
  $t .= "." if $t =~ /\S/;
  $t =~ s/\&ellip;/../g;
  return $t;
}

# Delete leading and trailing space from a string.
# Convert all whitespace to spaces. Convert multiple
# spaces to a single space.
sub norm
{
    my( $str ) = @_;

    return "" if not defined( $str );

    $str = Utf8Conv( $str );

    # Delete "bullet-character" used by Svt.
    $str =~ tr/\x95//d;

    $str =~ s/^\s+//;
    $str =~ s/\s+$//;

    $str =~ tr/\n\r\t /    /s;
    
    return $str;
}

1;
