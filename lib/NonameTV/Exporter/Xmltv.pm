package NonameTV::Exporter::Xmltv;

use strict;
use warnings;

use DateTime;
use XMLTV;

use NonameTV::Exporter;
use NonameTV::DataStore;

use base 'NonameTV::Exporter';

use constant LANG => 'sv';
our $OptionSpec     = [ qw/export-channels remove-old/ ];
our %OptionDefaults = ( 
                        'export-channels' => 0,
                        'remove-old' => 0,
                        );

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    defined( $self->{Root} ) or die "You must specify Root";

    return $self;
}

sub Export
{
  my( $self, $ds, $p ) = @_;
  
  if( $p->{'export-channels'} )
  {
    $self->ExportChannels( $ds );
    return;
  }

  if( $p->{'remove-old'} )
  {
    $self->RemoveOld( $ds );
    return;
  }

  # Check which batches have changed. 
  # Then: select distinct channel_id, DATE_FORMAT( start_time, '%Y-%m-%d' ) 
  # from programs where batch_id=1;

  # All at once ?
  # select distinct channel_id, DATE_FORMAT( start_time, '%Y-%m-%d' ) 
  # from programs, batches as b where (batch_id=b.id) and (b.last_update > ?);

  my $last_update = $ds->Lookup( 'state', { name => "xmltv_last_update" },
                                 'value' );

  if( not defined( $last_update ) )
  {
    $ds->Add( 'state', { name => "xmltv_last_update", value => 0 } );
    $last_update = 0;
  }

  $ds->Update( 'state', { name => "xmltv_last_update" }, { value => time() } );

  my( $ch_res, $ch_sth ) = $ds->Sql( 
"select distinct channel_id, DATE_FORMAT( start_time, '\%Y-\%m-\%d' ) as date
from programs, batches as b 
where (batch_id=b.id) and (b.last_update > $last_update)" );

  while( my $ch_data = $ch_sth->fetchrow_hashref() )
  {
    my $curr_date = $ch_data->{date};

    my $chd = $ds->Lookup( "channels", { id => $ch_data->{channel_id} } );
    my $curr_xmltv_id = $chd->{xmltvid};
  
    my $curr_channel_id = $ch_data->{channel_id};
    my $filename = $self->{Root} . $curr_xmltv_id . 
      "_" . $curr_date . ".xml";
  
    my $fh = new IO::File "> $filename"
      or die "cannot write to $filename";
  
    my $w = new XMLTV::Writer( encoding => 'ISO-8859-1',
                            OUTPUT   => $fh );
  
    $w->start({ 'generator-info-name' => 'nonametv' });
    
#    $w->write_channel( {
#      id => $chd->{xmltvid},
#      'display-name' => [[ $chd->{display_name}, LANG ]],
#   } );
    
    my( $res, $sth ) = $ds->Sql( "
      SELECT * from programs
      WHERE (channel_id = $curr_channel_id) 
        and (start_time > '$curr_date 00:00:00')
        and (start_time < '$curr_date 23:59:59') 
      ORDER BY start_time" );
  
    while( my $data = $sth->fetchrow_hashref() )
    {
      my $start_time = create_dt( $data->{start_time}, "UTC" );
      $start_time->set_time_zone( "Europe/Stockholm" );
      
      my $end_time = create_dt( $data->{end_time}, "UTC" );
      $end_time->set_time_zone( "Europe/Stockholm" );
      
      my $d = {
        channel => $curr_xmltv_id,
        start => $start_time->strftime( "%Y%m%d%H%M%S %z" ),
        stop => $end_time->strftime( "%Y%m%d%H%M%S %z" ),
        title => [ [ $data->{title}, LANG ] ],
      };
      
      $d->{desc} = [[ $data->{description}, LANG ]] 
        if defined( $data->{description} ) and $data->{description} ne "";
      $w->write_programme( $d );
    }

    # Close the output-file
    $w->end();
  }
}

#
# Write description of all channels to stdout.
#
sub ExportChannels
{
  my( $self, $ds ) = @_;

  my %w_args = ( encoding => 'ISO-8859-1',
                 DATA_INDENT => 2, 
                 DATA_MODE => 1);
  my $w = new XML::Writer( %w_args );

  $w->xmlDecl( 'iso-8859-1' );

  $w->startTag( 'tv', 'generator-info-name' => 'nonametv' );

  my( $res, $sth ) = $ds->Sql( "
      SELECT * from channels 
      ORDER BY xmltvid" );
  
  
  while( my $data = $sth->fetchrow_hashref() )
  {
    $w->startTag( 'channel', id => $data->{xmltvid} );
    $w->startTag( 'display-name', lang => 'sv' );
    $w->characters( $data->{display_name} );
    $w->endTag( 'display-name' );
    $w->startTag( 'base-url' );
    $w->characters( $self->{RootUrl} );
    $w->endTag( 'base-url' );
    $w->endTag( 'channel' );
  }
  
  $w->endTag( 'tv' );
  $w->end();
}

#
# Remove old xml-files and xml.gz-files. 
#
sub RemoveOld
{
  my( $self, $ds ) = @_;

  # Only keep files with data for yesterday and newer.
  my $dt = DateTime->today;
  $dt = $dt->subtract( days => 2 );


  my @files = glob( $self->{Root} . "*" );
  foreach my $file (@files)
  {
    my($year, $month, $day) = 
      ($file =~ /(\d\d\d\d)-(\d\d)-(\d\d)\.xml(\.gz){0,1}/);

    if( defined( $day ) )
    {
      my $date = DateTime->new( year => $year, month => $month, day => $day );
      unlink( $file )
        unless $date > $dt;
    }
  }

}

sub create_dt
{
  my( $str, $tz ) = @_;

  my( $year, $month, $day, $hour, $minute, $second ) =
    ( $str =~ /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$/ );

  die "Unknown time format $str" unless defined $second;

  return DateTime->new(
                       year => $year,
                       month => $month,
                       day => $day,
                       hour => $hour,
                       minute => $minute,
                       second => $second,
                       time_zone => $tz );
}
1;
