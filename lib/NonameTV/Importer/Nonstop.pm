package NonameTV::Importer::Nonstop;

use strict;
use warnings;

=pod

Importer for Nonstop TV, http://www.nonstop.tv/

=cut

use DateTime;
use XML::LibXML;
use POSIX qw/floor/;
use URI;

use NonameTV qw/MyGet Word2Xml Html2Xml norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/info progress error logdie/;

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

    $self->{toc} = {};

    return $self;
}

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $dsh = $self->{datastorehelper};

  my $doc;
    
  if( $$cref =~ /^\<\!DOCTYPE HTML/ ) {
    # This is an override that has already been run through wvHtml
    $doc = Html2Xml( $$cref );
  }
  else {
    $doc = Word2Xml( $$cref );
  }

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

sub FetchDataFromSite {
  my $self = shift;
  my( $batch_id, $data ) = @_;

  $self->FetchTOC( $data ) or return (undef, undef ); 

  my( $year, $week ) = ($batch_id =~ /_(\d+)-(\d+)/);

  my $url = $self->{toc}->{$data->{xmltvid}}->{"$year-$week"};
  
  if( not defined $url ) {
    error( "$batch_id: No link in TOC." );
    return (undef, 400 );
  }

  my( $content, $code ) = MyGet( $url );
  return( $content, $code );
}

sub FetchTOC {
  my $self = shift;
  my( $data ) = @_;

  return 1 if defined $self->{toc}->{$data->{xmltvid}};

  my %toc;

  my $base_url = $self->{UrlRoot} . $data->{grabber_info};
  my( $content, $code ) = MyGet( $base_url );

  my $doc = Html2Xml( $content );

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
