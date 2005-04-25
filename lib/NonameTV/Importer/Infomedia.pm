package NonameTV::Importer::Infomedia;

=pod

This importer imports data from www.infomedia.lu. The data is fetched
as one html-file per day and channel.

=cut

use strict;
use warnings;

use DateTime;
use XML::LibXML;

use NonameTV qw/MyGet Utf8Conv Html2Xml/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/get_logger start_output/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{grabber_name} = "Infomedia";

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $self->{datastorehelper} = $dsh;

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

  my $doc = Html2Xml( $$cref );
  
  if( not defined( $doc ) )
  {
    $l->error( "$batch_id: Failed to parse." );
    next;
  }
  
  # The data really looks like this...
  my $ns = $doc->find( '//tr[td/@class="schedtime"]' );
  if( $ns->size() == 0 )
  {
    $l->error( "$batch_id: No data found" );
    next;
  }
  
  $dsh->StartBatch( $batch_id, $chd->{id} );
  $dsh->StartDate( $date, "00:00" );
  
  foreach my $pgm ($ns->get_nodelist)
  {
    my $time = $pgm->findvalue( 'td[@class="schedtime"]//text()' );
    my $title = $pgm->findvalue( 'td[@class="schedtitle"]//text()' );
    my $subtitle = $pgm->findvalue( 'td[@class="schedepi"]//text()' );
    my $desc      = $pgm->findvalue( 'following-sibling::tr[1]' . 
                                     '/td[@class="light"]//text()' );


    my( $starttime ) = ( $time =~ /(\d+:\d+)/);
    
    my $ce =  {
      start_time  => $starttime,
      title       => norm($title),
      description => norm($desc),
    };
    
    $ce->{subtitle} = $subtitle if $subtitle =~ /\S/;

    extract_extra_info( $ce );
    $dsh->AddProgramme( $ce );
  }
  
  $dsh->EndBatch( 1 );
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my( $date ) = ($batch_id =~ /_(.*)/);

  # Date should be in format yyyymmdd.
  $date =~ tr/-//d;

  my $u = URI->new($self->{UrlRoot});
  $u->query_form( {
    chn => $data->{grabber_info},
    date => $date,
  });

  my( $content, $code ) = MyGet( $u->as_string );
  return( $content, $code );
}

sub extract_extra_info
{
  my( $ce ) = shift;

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
