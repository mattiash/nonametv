package NonameTV::Importer::TVNORGE;

=pod

This importer fetches a single XML-file from
TVNorges website. This file contains a whole month worth
of programinfo.

=cut

use strict;
use warnings;

use DateTime;
use XML::LibXML;

use NonameTV qw/MyGet norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/info progress error logdie/;

use NonameTV::Importer::BaseOne;

use base 'NonameTV::Importer::BaseOne';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);
    
    $self->{grabber_name} = "TVNORGE";
    
    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";
    
    
    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastorehelper} );
    $self->{datastorehelper} = $dsh;
    

}

sub ImportContent
{
    my $self = shift;
    
    my( $batch_id, $cref, $chd ) = @_;
    
    #my $ds = $self->{datastore};
    my $dsh = $self->{datastorehelper};
    
    $dsh->{SILENCE_END_START_OVERLAP}=1;
    
    my( $date ) = ($batch_id =~ /_(.*)$/);
    
    my $xml = XML::LibXML->new;
    my $doc;
    
    eval { $doc = $xml->parse_string($$cref); };
    if( $@ ne "" )
    {
        error( "$batch_id: Failed to parse $@" );
        return 0;
    }
    
    # Find all "sending" entries
    my $ns = $doc->find( "//item" );
    
    # Start date
    
    #$dsh->StartDate( $date, "00:00" );
    
    foreach my $sc ($ns->get_nodelist)
    {
    
        my $start = $sc->findvalue( './programDate' );
        $start =~ s/\./-/;
               
        # my $stop = $sc->findvalue( './SLUTTID' );
        # $stop =~ s/\./:/;
        
        my $title = $sc->findvalue( './programTitle' );
        my $subtitle = $sc->findvalue( './episodeTitle' );
#        if ($title eq "") {
#            $title = $subtitle;
#        }
        #my $bigtitle = "T$title - S$subtitle";
        #my $bigtitle = "$title: $subtitle" unless ($title eq $subtitle);
        #$bigtitle =~ s/^:.//;
#        if ($title eq $subtitle) {
#            $subtitle = "";
#        } else {
#            $title = "$title: $subtitle";
#            
#        }
        #if ($title eq "") {
        #    $title = $subtitle;
        #    $subtitle = "";
        #}
        
        my $desc = $sc->findvalue( './episodeText' );
        if ($desc eq "") {
            $desc = $sc->findvalue( './programListText' );
        }
        
        # my $text = $sc->findvalue( './TEKSTEKODE' );
        
        my $ce = {
            start_time  => $start,
            #end_time   => $stop,
            description => norm($desc),
            title       => norm($title),
            subtitle    => $subtitle,
            
        
        };
        
        $dsh->AddProgramme( $ce );
    
    
    }
    
    return 1;
}

sub FetchDataFromSite
{

    my $self = shift;
    my( $batch_id, $data ) = @_;
    #print $batch_id;

    my $u = $self->{UrlRoot};
    my ( $content, $code ) = MyGet ( $u );
    
    return( $content, $code );
}


sub createDate
{
    my $self = shift;
    my( $str ) = @_;
    
    my $date = substr( $str, 0, 2 );
    my $month = substr( $str, 2, 2 );
    my $year = substr( $str, 4, 4 );
    
    return "$year-$month-$date";

}

1;

