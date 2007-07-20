package NonameTV::Importer::Nonstop;

use strict;
use warnings;

=pod

Importer for Nonstop TV, http://www.nonstop.tv/

FIXME:
Cannot use FindParagraphs since ParseProgram looks for bold text.

=cut

use DateTime;
use XML::LibXML;
use POSIX qw/floor/;
use URI;

use NonameTV qw/MyGet Word2Xml Html2Xml norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/info progress error logdie 
                     log_to_string log_to_string_result/;

use NonameTV::ContentCache;

use NonameTV::Importer::BaseWeekly;

use base 'NonameTV::Importer::BaseWeekly';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{grabber_name} = "Nonstop";

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $self->{datastorehelper} = $dsh;

    $self->{cc} = NonameTV::ContentCache->new( { basedir => "/tmp/test" } );

    $self->{toc} = {};

    return $self;
}

sub FilterContent {
  my( $cref ) = @_;

  my $doc = Word2Xml( $$cref );
  my $str = $doc->toString();
  return \$str;
}

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $dsh = $self->{datastorehelper};

  my $doc = Html2Xml( $$cref );

  if( not defined( $doc ) ) {
    error( "$batch_id: Failed to parse" );
    return 0;
  }
  
  # Find all div-entries.
  my $ns = $doc->find( "//div" );
  
  if( $ns->size() == 0 ) {
    error( "$batch_id: No programme entries found" );
    return 0;
  }
  
  # States
  use constant {
    ST_START  => 0,
    ST_FDAY  => 1,  
    ST_FDATE  => 2,   # Found date
    ST_FPROGRAM => 3,   # Found program
  };
  
  use constant {
    T_DAY => 10,
    T_DATE => 11,
    T_PROGRAM => 12,
    T_ACTORS => 13,
        };
  
  my $state=ST_START;
  
  my $ce;

  foreach my $div ($ns->get_nodelist) {
    my( $text ) = norm( $div->findvalue( '.' ) );
    next if $text eq "";
    
    my $type;

    if( $text =~ /^(mon|tues|wednes|thurs|fri|satur|sun
		    |m.n|tis|ons|tors|fre|l.r|s.n)da(y|g)$/xi ) {
      $type = T_DAY;
    }
    elsif( $text =~ /^\d{1,2} \D+ \d{4}$/ ) {
      $type = T_DATE;
      my $date = ParseDate( $text );
      if( not defined $date ) {
        error( "$batch_id: Unknown date $text" );
        next;
      }
          
      $dsh->AddProgramme( $ce )
        if defined $ce;

      $ce = undef;

      $dsh->StartDate( $date, "00:00" ); 
    }
    elsif( $text =~ /^\d{1,2}:\d\d / ) {
      $type = T_PROGRAM;
      $dsh->AddProgramme( $ce )
        if defined $ce;

      $ce = ParseProgram( $div );
    }
    elsif( $text =~ /^with /i ) {
      $type = T_ACTORS;
      ParseActors( $text, $ce );
    }
    else {
      error( "$batch_id: Ignoring '$text'" );
      next;
    }
  }
  $dsh->AddProgramme( $ce )
    if defined $ce;

  # Success
  return 1;
}

sub FetchContent {
  my $self = shift;
  my( $batch_id, $data, $force_update ) = @_;

  $self->FetchTOC( $data ) or return undef; 

  my( $year, $week ) = ($batch_id =~ /_(\d+)-(\d+)/);

  my $url = $self->{toc}->{$data->{xmltvid}}->{"$year-$week"};
  
  if( not defined $url ) {
    # Let NonameTV::ContentCache handle error-messages.
    $self->{cc}->ReportError( $batch_id, "No such object in TOC." );
    return undef;
  }

  return $self->{cc}->GetContent( $batch_id, $url, \&FilterContent, 
				  $force_update );
}

sub FetchTOC {
  my $self = shift;
  my( $data ) = @_;

  return 1 if defined $self->{toc}->{$data->{xmltvid}};

  my %toc;

  my $base_url = $self->{UrlRoot} . $data->{grabber_info};
  my( $content, $code ) = $self->{cc}->GetUrl( $base_url );

  my $doc = Html2Xml( $$content );

  if( not defined( $doc ) ) {
    error( "$data->{xmltvid}: Failed to parse TOC" );
    return 0;
  }
  
  my $ns = $doc->find( "//a" );
  
  if( $ns->size() == 0 ) {
    error( "$data->{xmltvid}: No entries found in TOC" );
    return 0;
  }

  foreach my $a ($ns->get_nodelist) {
    my $text = norm( $a->findvalue( '.' ) );
    my $href = $a->findvalue( '@href' );

    next if $href !~ /\.doc$/i;
    next if $text =~ /highlight/i;

    my( $week, $year ) = ($text =~ /week\s+(\d{1,2}),\s*(\d{4})/i);
    next unless defined $year;

    # Change into integer to remove leading zeroes.
    $week = 0+$week;

    my $uri = URI->new_abs( $href, $base_url );
    $toc{$year . "-" . $week} = $uri->canonical->as_string;;
  }

  $self->{toc}->{$data->{xmltvid}} = \%toc;
  return 1;
}

sub ImportBatch {
  my $self = shift;
  my( $batch_id, $chd, $force_update ) = @_;

  # Log ERROR and FATAL
  my $h = log_to_string( 4 );

  info( "$batch_id: Fetching data" );

  my $ds;
  
  if( exists( $self->{datastorehelper} ) ) {
    $ds = $self->{datastorehelper};
  }
  else {
    $ds = $self->{datastore};
  }

  $ds->StartBatch( $batch_id, $chd->{id} );

  my $content_ref = $self->FetchContent( $batch_id, $chd, $force_update );
  
  if( defined( $content_ref ) ) {
    progress( "$batch_id: Processing data" );
    
    my $res = $self->ImportContent( $batch_id, $content_ref, $chd ); 
    
    my $message = log_to_string_result( $h );
    
    if( $res ) {
      # success
      $ds->EndBatch( 1, $message );
    }
    else {
      # failure
      $ds->EndBatch( 0, $message );
    }
  }
  else {
    # No new data.
    $ds->EndBatch( -1 );
    return;
  }
}

my %months = (
  january => 1,
  february => 2,
  march => 3,
  april => 4,
  may => 5,
  june => 6,
  july => 7,
  august => 8,
  september => 9,
  october => 10,
  november => 11,
  december => 12,

  januari=> 1,
  februari => 2,
  mars => 3,
  april => 4,
  maj => 5,
  juni => 6,
  juli => 7,
  augusti => 8,
  september => 9,
  oktober => 10,
  november => 11,
  december => 12,
);

sub ParseDate {
  my( $text ) = @_;

  my( $day, $month, $year ) = split( /\s+/, norm($text) );
  
  my $mn = $months{lc($month)};

  return undef if not defined $mn;

  return "$year-$mn-$day";
}

sub ParseProgram {
  my( $div ) = @_;

  my $ce;

  my $b = norm($div->findvalue('.//b'));
  my( $time, $title ) = ( $b =~ /^(\d{1,2}:\d{2}) (.+)/ );

  if( $title eq "CLOSEDOWN" ) {
    $ce->{title} = "end-of-transmission";
  }
  else {
    $ce->{title} = $title;
  }

  $ce->{start_time} = $time;

  my $description = norm( $div->findvalue('./p/text()' ) );
  my( $year ) = ($description =~ /^\((\d{4})\)\s*/);
  $description =~ s/^\(\d{4}\)\s*//;

  
  # Remove length-indication at end of description.
  $description =~ s/\s*\(\d+\)(\.*)$/$1/;
  
  $ce->{description} = $description if $description;
  $ce->{production_date} = "$year-01-01" if $year;
  
  return $ce;
}

sub ParseActors {
  my( $text, $ce ) = @_;

  $text =~ s/^with\s*//i;
  $text =~ s/\.$//i;

  my @actors = split(/\s*,\s*/, $text);
  $ce->{actors} = join( ", ", @actors );
}

1;
