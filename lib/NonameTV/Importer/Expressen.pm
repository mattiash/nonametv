package NonameTV::Importer::Expressen;

use strict;
use warnings;

=pod

Import data from Word-files delivered via e-mail. The parsing of the
data relies on data being presented in one table per day. Each day
is handled as a separate batch.

Features:

=cut

use DateTime;
use XML::LibXML;

use NonameTV qw/MyGet Wordfile2Xml Htmlfile2Xml Utf8Conv/;
use NonameTV::DataStore::Helper;

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
                                         { grabber => 'expressen' },
                                         qw/xmltvid id grabber_info/ )
    or die "Failed to fetch grabber data";

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
    print  "Expressen: Processing $file\n";
    $self->ImportFile( "", $file, $p );
  } 
}

sub ImportFile
{
  my $self = shift;
  my( $contentname, $file, $p ) = @_;

  # We only support one channel for Expressen.
  my $xmltvid="sport.expressen.se";

  my $channel_id = $self->{channel_data}->{$xmltvid}->{id};
  
  my $dsh = $self->{datastorehelper};
  
  my $doc;
  if( $file =~  /\.doc$/ )
  {
    $doc = Wordfile2Xml( $file );
  }
  elsif( $file =~ /\.html$/ )
  {
    $doc = Htmlfile2Xml( $file );
  }
  else
  {
    print "Expressen: Unknown extension $file\n";
  }
  
  if( not defined( $doc ) )
  {
    print STDERR "$file failed to parse\n";
    return;
  }
  
  # Find all table-entries.
  my $ns = $doc->find( "//table" );
  
  if( $ns->size() == 0 )
  {
    print STDERR "$file: No tables found.\n";
    return;
  }
  
  foreach my $table ($ns->get_nodelist)
  {
    my $ns2 = $table->find( ".//tr" );
    
    my $date = undef;
    foreach my $tr ($ns2->get_nodelist)
    {
      if( not defined( $date ) )
      {
        $date = norm( $tr->findvalue( './/td[2]//text()' ) );
        $date =~ /^\d\d\d\d-\d\d-\d\d$/ 
          or die "Invalid date $date";
        $dsh->StartBatch( "${xmltvid}_$date", $channel_id );
        $dsh->StartDate( $date );
        next;
      }

      my $starttime = norm( $tr->findvalue( './/td[1]//text()' ) );
      my $title = norm( $tr->findvalue( './/td[2]//text()' ) );
      my $description = norm( $tr->findvalue( './/td[3]//text()' ) );

      next if( $starttime !~ /\S.*\S/ );

      $starttime =~ tr/\./:/;
      if( $starttime !~ /^\d{1,2}:\d{1,2}$/ )
      {
        print STDERR "Expressen $date: Unknown starttime $starttime\n";
        next;
      }

      my $ce = {
        title       => $title,
        start_time  => $starttime,
      };

      # Some descriptions just contain a single non-alpha character.
      $ce->{description} = $description 
        if( $description =~ /[a-z]/ );

      extract_extra_info( $ce );

      $dsh->AddProgramme( $ce );
    }

    if( defined( $date ) )
    {
      $dsh->EndBatch( 1 );
    }
  } 
}

sub extract_extra_info
{
  my( $ce ) = shift;

  if( $ce->{title} =~ /^slut$/i )
  {
    $ce->{title} = "end-of-transmission";
  }

  return;
}

# Delete leading and trailing space from a string.
# Convert all whitespace to spaces. Convert multiple
# spaces to a single space.
sub norm
{
    my( $instr ) = @_;

    return "" if not defined( $instr );

    my $str = Utf8Conv( $instr );

    $str =~ tr/\n\r\t\xa0 /    /s; # a0 is nonbreaking space.

    $str =~ s/^\s+//;
    $str =~ s/\s+$//;
    
    return $str;
}

1;
