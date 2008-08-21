package NonameTV::Importer::Aftonbladet_http;

use strict;
use warnings;

=pod

Import data from Aftonbladet's website.

New scheduleformat at http://wwwc.aftonbladet.se/atv/pressrum/tabla/50.html

Features:

=cut

use utf8;

use DateTime;
use XML::LibXML;

use NonameTV qw/MyGet Html2Xml FindParagraphs norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error 
                     log_to_string log_to_string_result/;

use NonameTV::Importer::BaseWeekly;

use base 'NonameTV::Importer::BaseWeekly';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  $self->{grabber_name} = "Aftonbladet_http";

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  my $doc = Html2Xml( $$cref );
  
  if( not defined $doc ) {
    return (undef, "Html2Xml failed" );
  } 

  my $paragraphs = FindParagraphs( $doc, 
      "//table//." );

  my $str = join( "\n", @{$paragraphs} );
  
  return( \$str, undef );
}

sub ContentExtension {
  return 'html';
}

sub FilteredExtension {
  return 'txt';
}

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  $self->{batch_id} = $batch_id;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};

  my $dsh = $self->{datastorehelper};

  my @paragraphs = split( /\n/, $$cref );

  if( scalar(@paragraphs) == 0 ) {
    error( "$batch_id: No paragraphs found." ) ;
    return 0;
  }

  my $currdate = undef;
  my $ce = undef;
  my $prev_start ="x";

  foreach my $text (@paragraphs) {
    next if $text =~/^Releaser.*Bilder.*Kontakt$/i;
    next if $text =~/^TV7-TABL. VECKA \d+/i;


    if( ($text =~ /^\S+dag \d{1,2} \S+ \d{1,2}\.\d\d\b/i) or
	($text =~ /^\S+dag \d{1,2} \S+$/i) ) {
      my $date = $self->ParseDate( $text );
      if( not defined $date ) {
        error( "$batch_id: Unknown date $text" );
        next;
      }
          
      if( defined $ce ) {
        $prev_start = $ce->{start_time};
        $dsh->AddProgramme( $ce );
      }

      $ce = undef;

      $dsh->StartDate( $date, "06:00" ); 
      $currdate = $date;

      # The first program usually follows in the same paragraph as the date.
      # Remove the date and continue processing the paragraph.
      $text =~ s/^\S+dag \d{1,2} \S+ *//i;
      next if $text eq "";
    }

    if( $text =~ /^\d{1,2}.\d\d(\s*-\s*\d{1,2}.\d\d){0,1} / ) {
      if( defined $ce ) {
	$ce->{description} = norm( $ce->{description} );

        # Aftonbladet uses program-blocks that contain several
        # sub-programmes. Ignore the first sub-programme.
        my $t = $ce->{start_time};
        $dsh->AddProgramme( $ce )
          if $ce->{start_time} ne $prev_start;
        $prev_start = $t
      }
      $ce = ParseProgram( $text );
      $ce->{description} = "";
    }
    else {
      if( not defined $ce ) {
        error( "$batch_id: Ignoring text $text" );
        next;
      }
      $ce->{description} .= " $text";
    }
  }

  if( defined $ce ) {
    $ce->{description} = norm( $ce->{description} );
    $dsh->AddProgramme( $ce );
  }

  return 1;
}

my %months = (
              jnauari => 1,
              januari => 1,
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
  my $self = shift;
  my( $text ) = @_;

  my( $wday, $day, $month ) = ($text =~ /^(\S+) (\d+) ([a-z]+)\b/i);
  my $monthnum = $months{lc $month};

  if( not defined $monthnum ) {
    error( $self->{batch_id} . ": Unknown month '$month' in '$text'" );
    return undef;
  }
  
  my $dt = DateTime->today();
  $dt->set( month => $monthnum, day => $day );
 
  if( $dt > DateTime->today()->add( days => 180 ) ) {
    $dt->add( years => -1 );
  }
  elsif( $dt < DateTime->today()->add( days => -180 ) ) {
    $dt->add( years => 1 );
  }

  return $dt->ymd('-');
}

sub ParseProgram {
  my( $text ) = @_;

  my( $start, $stop, $title );

  ($start, $stop, $title) = ($text =~ 
                             /^(\d{1,2}\.\d\d)
                             \s*-\s*
                             (\d{1,2}\.\d\d)
                             \s*
                             (.*)$/ix );
  if( not defined $title ) {
    ($start, $title) = ($text =~
                        /^(\d{1,2}\.\d\d)
                        \s*
                        (.*)$/ix );
  }

  if( not defined( $title ) ) {
    error( "Unknown: $text" );
    return undef;
  }
  
  $start =~ tr/\./:/;

  my $ce = {
    start_time => $start,
    title => $title,
  };

  if( defined $stop ) {
    $stop =~ tr/\./:/;
    $ce->{end_time} = $stop;
  }

  return $ce;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $week ) = ( $objectname =~ /(\d+)-(\d+)$/ );
 
  my $url = sprintf( "%s/%d.html", $self->{UrlRoot}, $week );
  
  return( $url, undef );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
