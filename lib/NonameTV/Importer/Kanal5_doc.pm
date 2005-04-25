package NonameTV::Importer::Kanal5_doc;

use strict;
use warnings;

=pod

Importer for Kanal5's Word-format.
Data is downloaded in one file per week. The file is in Microsoft Word-
format. There is no consistent markup used for describing the data. The
parsing is done by iterating over each <div> in the resulting html and
looking at the text inside the <div> to decide what type of data is
in this <div>. This is then fed to a state-machine.

The Importer also accepts data in html-format as produced by wvHtml.
This makes it possible to provide overrides in html-format.

Categorization-data is fetched from the xml-files that Kanal5 publish.
These files contain more data than the Word-files, but they are not
updated with last minute changes. Programs are matched between the
two formats by looking for identical titles.

Features:

Episode-information parsed from description.

=cut

use DateTime;
use XML::LibXML;
use POSIX qw/floor/;

use NonameTV qw/MyGet Word2Xml Html2Xml Utf8Conv AddCategory ParseDescCatSwe/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/get_logger start_output/;

use NonameTV::Importer::BaseWeekly;

use base 'NonameTV::Importer::BaseWeekly';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{grabber_name} = "Kanal5";

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $self->{datastorehelper} = $dsh;

    return $self;
}

sub ImportContent
{
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my $cat = $self->FetchCategories( $batch_id, $chd );

  my $dsh = $self->{datastorehelper};
  my $l = $self->{logger};

  my $doc;
    
  if( $$cref =~ /^\<\!DOCTYPE HTML/ )
  {
    # This is an override that has already been run through wvHtml
    $doc = Html2Xml( $$cref );
  }
  else
  {
    $doc = Word2Xml( $$cref );
  }

  if( not defined( $doc ) )
  {
    $l->error( "$batch_id: Failed to parse" );
    return;
  }
  
  # Find all div-entries.
  my $ns = $doc->find( "//table//div" );
  
  if( $ns->size() == 0 )
  {
    $l->error( "$batch_id: No programme entries found" );
    return;
  }
  
  $dsh->StartBatch( $batch_id, $chd->{id} );
  
  # States
  use constant {
    ST_START  => 0,
    ST_FDATE  => 1,   # Found date
    ST_FTIME  => 2,   # Found starttime
    ST_FTITLE => 3,   # Found title
    ST_FDESC  => 4,   # Found description
  };
  
  use constant {
    T_TIME => 10,
    T_DATE => 11,
    T_TEXT => 12,
        };
  
  my $state=ST_START;
  my $currdate;
  
  my $ce = {};
  
  foreach my $div ($ns->get_nodelist)
  {
    my( $text ) = norm( $div->findvalue( '.' ) );
    next if $text eq "";
    
    my $type = T_TEXT;
    
    my( $date ) = ($text =~ 
		   /^\s*\S+\s+
		   (\d+-\d+-\d+),\s+
		   vecka\s+\d+,\s+
		   Kanal\s+5\s*$/x )
	and $type = T_DATE;
    
    my( $start, $stop );
    
    if( ($start, $stop) = ( $text =~ /^(\d+:\d+)\s*\-\s*(\d+:\d+)$/ ) )
    {
      $type = T_TIME;
    }
    elsif( ( $start ) = ( $text =~ /^(\d+:\d+)$/ ) )
    {
      $type = T_TIME;
    }
    
    if( $state == ST_FTITLE )
    {
      if( $type == T_TEXT )
      {
	if( defined( $ce->{description} ) )
	{
	  $ce->{description} .= " " . $text;
	}
	else
	{
	  $ce->{description} = $text;
	}
      }
      else
      {
	$self->extract_extra_info( $ce, $cat, $batch_id );
	$dsh->AddProgramme( $ce );
	$ce = {};
	$state = ST_FDATE;
      }
    }
    
    if( $state == ST_START )
    {
      if( $type == T_DATE )
      {
	$dsh->StartDate( $date );
	$state = ST_FDATE;
      }
      else
      {
	$l->error( "$batch_id: Expected date, found: $text" );
      }
    }
    elsif( $state == ST_FDATE )
    {
      if( $type == T_TIME )
      {
	$ce->{start_time} = $start;
	$ce->{end_time} = $stop if defined( $stop );
	$state = ST_FTIME;
      }
      elsif( $type == T_DATE )
      {
	$dsh->StartDate( $date );
	$state = ST_FDATE;
      }
      else
      {
	$l->error( "$batch_id: Expected time, found: $text" );
      }
    }
    elsif( $state == ST_FTIME )
    {
      if( $type == T_TEXT )
      {
	$ce->{title} = $text;
	$state = ST_FTITLE;
      }
      else
      {
	$l->error( "$batch_id: Expected title, found: $text" );
      }
    }
  }
  
  if( defined( $ce->{title} ) )
  {
    $self->extract_extra_info( $ce, $cat, $batch_id );
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
  my( $batch_id, $data ) = @_;

  $batch_id .= ".xml";

  my $ds = $self->{datastore};
  my $l = $self->{logger};

  my $cat = {};

  $l->info( "$batch_id: Fetching categories" );

  my( $content, $code ) = $self->FetchData( $batch_id , $data );
            
  if( not defined( $content ) )
  {
    $l->error( "$batch_id: Failed to fetch listings" );
    return $cat;
  }
   
  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_string($content); };
  if( $@ ne "" )
  {
    $l->error( "$batch_id: Failed to parse" );
    return $cat;
  }
  
  # Find all "TRANSMISSION"-entries.
  my $ns = $doc->find( "//TRANSMISSION" );
  
  if( $ns->size() == 0 )
  {
    $l->error( "$batch_id: No programme entries found" );
    return $cat;
  }
  
  foreach my $tm ($ns->get_nodelist)
  {
    my $title =norm( $tm->findvalue(
      './/PRODUCTTITLE[.//PSIPRODUCTTITLETYPE/@oid="131708570"][1]/@title') );
    
    if( $title =~ /^\s*$/ )
    {
      # Some entries lack a title. 
      # Fallback to the title in the TRANSMISSION-tag.
      $title = norm( $tm->findvalue( '@title' ) );
    }
    
    my $category = norm( $tm->findvalue( './/CATEGORY/@name' ) );
    
    if( $title =~ /^\s*$/ )
    {
      # No title. Skip it.
      next;
    }
    
    if( $category =~ /^\s*$/ )
    {
      # No title. Skip it.
      next;
    }
    
    $cat->{$title} = $category;
  }

  return $cat;
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my( $year, $week, $ext ) = ($batch_id =~ /_20(\d+)-(\d+)(.*)/);

  $ext = ".doc" unless $ext;

  my $url = sprintf( "%stab%02d%02d%s", $self->{UrlRoot}, $week, $year, $ext );

  my( $content, $code ) = MyGet( $url );
  return( $content, $code );
}

sub extract_extra_info
{
  my $self = shift;
  my( $ce, $cat, $batch_id ) = @_;

  my $ds = $self->{datastore};
  my $l = $self->{logger};

  # Try to remove any prefix such as "SERIESTART:" from the title.
  # These prefixes are only available in the doc-data, not in the
  # xml-files.
  my( $short_title ) = ($ce->{title} =~ /:\s*(.*)/);
  if( defined($short_title) and defined( $cat->{$short_title} ) )
  {
    $ce->{title} = $short_title;
  }

  my( $program_type, $category );

  #
  # Lookup category and program_type by searching for the title in
  # the xml-data.
  #
  if( defined( $cat->{$ce->{title}} ) )
  {
    ( $program_type, $category ) = $ds->LookupCat( "Kanal5",
                                                   $cat->{$ce->{title}} );
    AddCategory( $ce, $program_type, $category );
  }
  else
  {
    $l->info( "$batch_id: No category found for $ce->{title}" );
  }

  extract_episode( $ce );

  #
  # Try to extract category and program_type by matching strings
  # in the description.
  #
  ( $program_type, $category ) = ParseDescCatSwe( $ce->{description} );
  AddCategory( $ce, $program_type, $category );

  #
  # Add default category and program_type from the category-information
  # in the xml-file if all the above failed.
  #
  if( defined( $cat->{$ce->{title}} ) )
  {
    ( $program_type, $category ) = $ds->LookupCat( "Kanal5_fallback",
                                                   $cat->{$ce->{title}} );
    AddCategory( $ce, $program_type, $category );
  }

  # Find production year from description.
  if( defined( $ce->{description} ) and
      ($ce->{description} =~ /\bfr.n (\d\d\d\d)\b/) )
  {
    $ce->{production_date} = "$1-01-01";
  }
}

sub extract_episode
{
  my( $ce ) = @_;

  #
  # Try to extract episode-information from the description.
  #
  my( $ep, $eps, $seas );
  my $episode;

  my $d = $ce->{description};

  return unless defined( $d );

  # Avsn 2
  ( $ep ) = ($d =~ /\s+Avsn\s+(\d+)/ );
  $episode = sprintf( " . %d .", $ep-1 ) if defined $ep;

  # Avsn 2/3
  ( $ep, $eps ) = ($d =~ /\s+Avsn\s+(\d+)\s*\/\s*(\d+)/ );
  $episode = sprintf( " . %d/%d . ", $ep-1, $eps ) 
    if defined $eps;

  # Avsn 2/3 säs 2.
  ( $ep, $eps, $seas ) = ($d =~ /\s+Avsn\s+(\d+)\s*\/\s*(\d+)\s+s.s\s+(\d+)/ );
  $episode = sprintf( " %d . %d/%d . ", $seas-1, $ep-1, $eps ) 
    if defined $seas;

  # Avsn 2 säs 2.
  ( $ep, $seas ) = ($d =~ /\s+Avsn\s+(\d+)\s+s.s\s+(\d+)/ );
  $episode = sprintf( " %d . %d . ", $seas-1, $ep-1 ) 
    if defined $seas;

  # Del 2
  ( $ep ) = ($d =~ /\s+Del\s+(\d+)/ );
  $episode = sprintf( " . %d .", $ep-1 ) if defined $ep;

  # Del 2/3
  ( $ep, $eps ) = ($d =~ /\s+Del\s+(\d+)\s*\/\s*(\d+)/ );
  $episode = sprintf( " . %d/%d . ", $ep-1, $eps ) 
    if defined $eps;

  # Del 2/3 säs 2.
  ( $ep, $eps, $seas ) = ($d =~ /\s+Del\s+(\d+)\s*\/\s*(\d+)\s+s.s\s+(\d+)/ );
  $episode = sprintf( " %d . %d/%d . ", $seas-1, $ep-1, $eps ) 
    if defined $seas;

  # Del 2 säs 2.
  ( $ep, $seas ) = ($d =~ /\s+Del\s+(\d+)\s+s.s\s+(\d+)/ );
  $episode = sprintf( " %d . %d . ", $seas-1, $ep-1 ) 
    if defined $seas;
  
  if( defined $episode )
  {
    $ce->{episode} = $episode;
    $ce->{program_type} = 'series';
  }
}
  
# Delete leading and trailing space from a string.
# Convert all whitespace to spaces. Convert multiple
# spaces to a single space.
sub norm
{
    my( $str ) = @_;

    return "" if not defined( $str );

    $str = Utf8Conv( $str );

    $str =~ s/^\s+//;
    $str =~ s/\s+$//;

    $str =~ tr/\n\r\t /    /s;

    return $str;
}

1;
