package NonameTV::Importer::Viasat;

use strict;
use warnings;

=pod

Import data from Viasat's press-site. The data is downloaded in
tab-separated text-files.

Features:

Proper episode and season fields. The episode-field contains a
number that is relative to the start of the series, not to the
start of this season.

program_type

=cut


use DateTime;
use Encode;

use NonameTV qw/MyGet expand_entities AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/info progress error logdie/;

use NonameTV::Importer::BaseWeekly;

use base 'NonameTV::Importer::BaseWeekly';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{grabber_name} = 'Viasat';

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $self->{datastorehelper} = $dsh;

    return $self;
}

sub ImportContent
{
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  # Decode the string into perl's internal format.
  # see perldoc Encode

#  my $str = decode( "utf-8", $$cref );
  my $str = decode( "iso-8859-1", $$cref );
 
 
  # The encode step should really be performed as the last
  # step before sending the data outside of perl.
  $str = encode( "iso-8859-1", $str );

  my @rows = split("\n", $str );

  if( scalar( @rows < 2 ) )
  {
    error( "$batch_id: No data found" );
    return 0;
  }

  my $columns = [ split( "\t", $rows[0] ) ];

  for ( my $i = 1; $i < scalar @rows; $i++ )
  {
    my $inrow = $self->row_to_hash($batch_id, $rows[$i], $columns );
    
    if ( exists($inrow->{'Date'}) )
    {
      $dsh->StartDate( $inrow->{'Date'} );
    }
    
    my $start = $inrow->{'Start time'};
    
    my $description = $inrow->{'Synopsis this episode'}
    || $inrow->{'Synopsis'}; 
    
    $description = norm( $description );
    
    # Episode info in xmltv-format
    my $ep_nr = $inrow->{'episode nr'} || 0;
    my $ep_se = $inrow->{'Season number'} || 0;
    my $episode = undef;
    
    if( ($ep_nr > 0) and ($ep_se > 0) )
    {
      $episode = sprintf( "%d . %d .", $ep_se-1, $ep_nr-1 );
    }
    elsif( $ep_nr > 0 )
    {
      $episode = sprintf( ". %d .", $ep_nr-1 );
    }

    my $ce = {
      title => norm( $inrow->{'name'} ),
      description => $description,
      start_time => $start,
      episode => $episode,
      Viasat_category => norm( $inrow->{Category} ),
      Viasat_genre => norm( $inrow->{Genre} ),
    };

    if( defined( $inrow->{'Production Year'} ) and
        $inrow->{'Production Year'} =~ /(\d\d\d\d)/ )
    {
      $ce->{production_date} = "$1-01-01";
    }

    my $cast = norm( $inrow->{'Cast'} );
    if( $cast =~ /\S/ )
    {
      # Remove all variants of m.fl.
      $cast =~ s/\s*m[\. ]*fl\.*\b//;

      # Remove trailing '.'
      $cast =~ s/\.$//;

      my @actors = split( /\s*,\s*/, $cast );
      foreach (@actors)
      {
        # The character name is sometimes given in parentheses. Remove it.
        # The Cast-entry is sometimes cutoff, which means that the
        # character name might be missing a trailing ).
        s/\s*\(.*$//;
      }
      $ce->{actors} = join( ", ", grep( /\S/, @actors ) );
    }

    my $director = norm( $inrow->{'Director'} );
    if( $director =~ /\S/ )
    {
      # Remove all variants of m.fl.
      $director =~ s/\s*m[\. ]*fl\.*\b//;
      
      # Remove trailing '.'
      $director =~ s/\.$//;
      my @directors = split( /\s*,\s*/, $director );
      $ce->{directors} = join( ", ", grep( /\S/, @directors ) );
    }

    $self->extract_extra_info( $ce );
    $dsh->AddProgramme( $ce );
  }

  # Success
  return 1;
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my( $year, $week ) = ( $batch_id =~ /(\d+)-(\d+)$/ );
 
  my $url = sprintf( "%s%s%02d-%02d_tab.txt",
                     $self->{UrlRoot}, $data->{grabber_info}, 
                     $year, $week );
  
  my( $content, $code ) = MyGet( $url );
  return( $content, $code );
}

sub row_to_hash
{
  my $self = shift;
  my( $batch_id, $row, $columns ) = @_;

  my @coldata = split( "\t", $row );
  my %res;
  
  if( scalar( @coldata ) != scalar( @{$columns} ) )
  {
    error( "$batch_id: Wrong number of columns " .
           scalar( @coldata ) . " != " . 
           scalar( @{$columns} ) );
  }

  for( my $i=0; $i<scalar(@coldata) and $i<scalar(@{$columns}); $i++ )
  {
    $res{$columns->[$i]} = norm($coldata[$i])
      if $coldata[$i] =~ /\S/; 
  }

  return \%res;
}

sub extract_extra_info
{
  my $self = shift;

  my( $ce ) = @_;

  my $ds = $self->{datastore};

  my $ltitle = lc $ce->{title};

  if ( ($ltitle eq "slut") or
       ($ltitle eq "godnatt") or
       ($ltitle eq "end") or
       ($ltitle eq "close") )               
  {
    $ce->{title} = "end-of-transmission";
  }

  # Remove trailing . from category.
  my $viasat_cat = $ce->{Viasat_category};
  $viasat_cat =~ s/\.\s*$//;
  
  my( $pty, $cat ) = $ds->LookupCat( 'Viasat_category', $viasat_cat );
  AddCategory( $ce, $pty, $cat );
  
  my $viasat_genre = $ce->{Viasat_genre};
  $viasat_genre =~ s/\.\s*$//;

  ( $pty, $cat ) = $ds->LookupCat( 'Viasat_genre', $viasat_genre );
  AddCategory( $ce, $pty, $cat );
  
  delete( $ce->{Viasat_category} );
  delete( $ce->{Viasat_genre} );
}

# Delete leading and trailing space from a string.
# Convert all whitespace to spaces. Convert multiple
# spaces to a single space.
sub norm
{
    my( $str ) = @_;

    return "" if not defined( $str );

# This doesn't work. The Utf8Conv is now performed on the whole input-file
# at once instead.
#    $str = Utf8Conv( $str );
    
#    $str = decode_entities( $str );
    $str = expand_entities( $str );

    $str =~ s/^\s+//;
    $str =~ s/\s+$//;

    $str =~ tr/\n\r\t /    /s;

    # Strange quote-sign.
    $str =~ tr/\x93\x94\x96/""-/;

    return $str;
}

1;
