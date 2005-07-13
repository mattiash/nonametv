package NonameTV::Exporter::Xmltv;

use strict;
use warnings;

use IO::File;
use DateTime;
use XMLTV;
use DateTime::SpanSet;
use File::Copy;

use NonameTV::Exporter;
use NonameTV::XmltvValidate qw/xmltv_validate_file/;

use NonameTV::Log qw/get_logger start_output/;

use base 'NonameTV::Exporter';

=pod

Export data in xmltv format.

Options:

  --verbose
    Show which datafiles are created.

  --export-channels
    Print a list of all channels in xml-format to stdout.

  --remove-old
    Remove any old xmltv files from the output directory.

  --force-export
    Recreate all output files, not only the ones where data has
    changed.

=cut 

use constant LANG => 'sv';
our $OptionSpec     = [ qw/export-channels remove-old force-export 
                           verbose help/ ];
our %OptionDefaults = ( 
                        'export-channels' => 0,
                        'remove-old' => 0,
                        'force-export' => 0,
                        'help' => 0,
                        'verbose' => 0,
                        );

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    defined( $self->{Root} ) or die "You must specify Root";
    $self->{MaxDays} = 365 unless defined $self->{MaxDays};

    return $self;
}

my $l; 

sub Export
{
  my( $self, $ds, $p ) = @_;

  if( $p->{'help'} )
  {
    print << 'EOH';
Export data in xmltv-format with one file per day and channel.

Options:

  --export-channels
    Generate an xml-file listing all channels and their corresponding
    base url.

  --remove-old
    Remove all data-files for dates that have already passed.

  --force-export
    Export all data. Default is to only export data for batches that
    have changed since the last export.

EOH

    return;
  }

  $l=get_logger(__PACKAGE__);
  start_output( __PACKAGE__, $p->{verbose} );

  if( $p->{'export-channels'} )
  {
    $self->ExportChannels( $ds );
    return;
  }

  if( $p->{'remove-old'} )
  {
    $self->RemoveOld( $ds, $p );
    return;
  }

  $self->ExportData( $ds, $p );
}

#
# Write description of all channels to stdout.
#
sub ExportChannels
{
  my( $self, $ds ) = @_;

  my $output = new IO::File("> $self->{Root}channels.xml");
  
  my %w_args = ( encoding    => 'ISO-8859-1',
                 DATA_INDENT => 2, 
                 DATA_MODE   => 1,
                 OUTPUT      => $output,
                 );
  my $w = new XML::Writer( %w_args );

  $w->xmlDecl( 'iso-8859-1' );

  $w->startTag( 'tv', 'generator-info-name' => 'nonametv' );

  my( $res, $sth ) = $ds->Sql( "
      SELECT * from channels 
      WHERE export=1
      ORDER BY xmltvid" );
  
  
  while( my $data = $sth->fetchrow_hashref() )
  {
    $w->startTag( 'channel', id => $data->{xmltvid} );
    $w->startTag( 'display-name', lang => $data->{sched_lang} );
    $w->characters( $data->{display_name} );
    $w->endTag( 'display-name' );
    $w->startTag( 'base-url' );
    $w->characters( $self->{RootUrl} );
    $w->endTag( 'base-url' );
    if( $data->{logo} )
    {
      $w->emptyTag( 'icon', 
                    src => $self->{IconRootUrl} . 
                           $data->{xmltvid} .  ".png"  );
    }
    $w->endTag( 'channel' );
  }
  
  $w->endTag( 'tv' );
  $w->end();
  system("gzip -f -n $self->{Root}channels.xml");
}

#
# Remove old xml-files and xml.gz-files. 
#
sub RemoveOld
{
  my( $self, $ds, $p ) = @_;

  # Keep files for the last week.
  my $dt = DateTime->today;
  my $keep_date = $dt->subtract( days => 8 )->ymd("-");

  my @files = glob( $self->{Root} . "*" );
  my $removed = 0;

  foreach my $file (@files)
  {
    my($date) = 
      ($file =~ /(\d\d\d\d-\d\d-\d\d)\.xml(\.gz){0,1}/);

    if( defined( $date ) )
    {
      # Compare date-strings.
      if( $date lt $keep_date )
      {
        $l->info( "Xmltv: Removing $file" );
        unlink( $file );
        $removed++;
      }
    }
  }

  $l->warn( "Xmltv: Removed $removed files" )
    if( $removed > 0 );
}

sub create_dt
{
  my( $str, $tz ) = @_;

  my( $year, $month, $day, $hour, $minute, $second ) =
    ( $str =~ /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$/ );

  $l->logdie( "Xmltv: Unknown time format $str" )
    unless defined $second;

  return DateTime->new(
                       year => $year,
                       month => $month,
                       day => $day,
                       hour => $hour,
                       minute => $minute,
                       second => $second,
                       time_zone => $tz );
}

sub AddDate
{
  my( $upd, $channel_id, $date ) = @_;

  $upd->{$channel_id} = DateTime::SpanSet->empty_set()
      unless defined( $upd->{$channel_id} );
  
  my( $year, $month, $day ) = split( "-", $date );
  my $dt = DateTime->new( year => $year, month => $month, day => $day );
  
  my $span = DateTime::Span->from_datetime_and_duration(
	start => $dt, days => 1 );
  
  my $spanset = $upd->{$channel_id};
  
  $spanset = $spanset->union( $span );
  $upd->{$channel_id} = $spanset;
}

sub ExportData
{
  my $self = shift;
  my( $ds, $p ) = @_;

  $self->{outf}=sub {
    my( $file, $line, $err ) = @_;
    $l->info( "$file $line: $err" );
  };
  
  my $last_update = $ds->Lookup( 'state', { name => "xmltv_last_update" },
                                 'value' );

  if( not defined( $last_update ) )
  {
    $ds->Add( 'state', { name => "xmltv_last_update", value => 0 } );
    $last_update = 0;
  }

  my $export_from = $ds->Lookup( 'state', 
                                 { name => "xmltv_exported_until" },
                                 'value' );
  
  if( not defined( $export_from ) )
  {
    $export_from = DateTime->today->subtract( days => 1 )->ymd("-");
    $ds->Add( 'state', { name => "xmltv_exported_until", 
                         value => $export_from } );
  }

  my $export_from_dt = create_dt( "$export_from 00:00:00", "UTC" );

  my $export_until_dt = DateTime->today->add( days => $self->{MaxDays} -1 ); 
  my $export_until = $export_until_dt->ymd("-");

  my $update_started = time();

  my $upd = {};

  if( not $p->{'force-export'} )
  {
    #
    # Find out which dates have been updated for each channel
    # since the last export.
    #
    my $today = DateTime->today->ymd('-');

    my( $ch_res, $ch_sth ) = $ds->Sql( 
      "select distinct
       channel_id,
       DATE_FORMAT( start_time, '\%Y-\%m-\%d' ) as date
       from programs, batches as b 
       where (batch_id=b.id) and (b.last_update > $last_update) 
         and (start_time >= '$today 00:00:00')
         and (start_time <= '$export_until 23:59:59')
      " );

    while( my $ch_data = $ch_sth->fetchrow_hashref() )
    {
      AddDate( $upd, $ch_data->{channel_id}, $ch_data->{date} );
    }
    
    $ch_sth->finish();
  }
  else
  {
    $export_from_dt = DateTime->today->subtract( days => 1 );
    $export_from = $export_from_dt->ymd("-");
  }

  # 
  # Add dates that haven't yet been exported.
  #

  my @newdates;
  
  my $dt = $export_from_dt->clone()->add( days => 1 );
  while( $dt <= $export_until_dt )
  {
    push @newdates, $dt->ymd('-');
    $dt->add( days=> 1 );
  }

  my ( $ch_res, $ch_sth ) = $ds->Sql( "select id from channels " );

  while( my $ch_data = $ch_sth->fetchrow_hashref() )
  {
    foreach my $date (@newdates)
    {
      AddDate( $upd, $ch_data->{id}, $date );
    }
  }

  $ch_sth->finish();

  foreach my $channel (keys %{$upd})
  {
    my $chd = $ds->Lookup( "channels", { id => $channel } );
    
    # Skip channels that shouldn't be exported.
    next unless $chd->{export};

    my $iter = $upd->{$channel}->iterator;
    while ( my $dt = $iter->next ) 
    {
      $self->export_range( $ds, $dt, $channel, $chd, $p );
    }
  }

  $ds->Update( 'state', { name => "xmltv_last_update" }, 
               { value => $update_started } );
  $ds->Update( 'state', { name => "xmltv_exported_until" },
               { value => $export_until } );
}

sub export_range
{
  my $self = shift;
  my( $ds, $dt, $channelid, $chd, $p ) = @_;

  # $dt is a DateTime::Span
  my $startdate = $dt->start->ymd('-');
  my $enddate = $dt->end->ymd('-');
  
  # Keep track of which dates should be exported.
  my %dates;
  my $d = $dt->start->clone();
  while( $d < $dt->end )
  {
    $dates{$d->ymd('-')} = 1;
    $d->add( days => 1 );
  }
  
  my( $res, $sth ) = $ds->Sql( "
        SELECT * from programs
        WHERE (channel_id = ?) 
          and (start_time >= ?)
          and (start_time < ?) 
        ORDER BY start_time", 
      [$channelid, "$startdate 00:00:00", "$enddate 23:59:59"] );
  
  my $d1 = $sth->fetchrow_hashref();
  if( defined( $d1 ) )
  {
    my $done = 0;
    my( $date ) = split( " ", $d1->{start_time} );
    my $w = $self->create_writer( $chd->{xmltvid}, $date, $p );
    
    # Make a note that a file has been created for this date.
    $dates{$date} = 0;
    
    while( (not $done) and (my $d2=$sth->fetchrow_hashref()) )
    {
      if( (not defined( $d1->{end_time})) or
          ($d1->{end_time} eq "0000-00-00 00:00:00") )
      {
        # Fill in missing end_time on the previous entry with the start-time
        # of the current entry
        $d1->{end_time} = $d2->{start_time}
      }
      elsif( $d1->{end_time} gt $d2->{start_time} )
      {
        # The previous programme ends after the current programme starts.
        # Adjust the end_time of the previous programme.
        $l->warn( "Xmltv: Adjusted endtime for $chd->{xmltvid}: " . 
                  "$d1->{end_time} => $d2->{start_time}" );

        $d1->{end_time} = $d2->{start_time}
      }        
      
      my( $date1 ) = split( " ", $d1->{start_time} );
      if( $date1 ne $date )
      {
        $date = $date1;
        if( $date ge $enddate )
        {
          $done=1;
          last;
        }
        $self->close_writer( $w );
        $w = $self->create_writer( $chd->{xmltvid}, $date, $p );
        
        # Make a note that a file has been created for this date.
        $dates{$date} = 0;
      }
      $self->write_entry( $w, $d1, $chd )
        unless $d1->{title} eq "end-of-transmission";
      $d1 = $d2;
    }

    if( not $done )
    {
      # The loop exited because we ran out of data. This means that
      # there is no data for the day after the last day that we
      # wanted to export. Make sure that we write out the last entry
      # if we know the end-time for it.
      if( (defined( $d1->{end_time})) and
          ($d1->{end_time} ne "0000-00-00 00:00:00") )
      {
        $self->write_entry( $w, $d1, $chd )
          unless $d1->{title} eq "end-of-transmission";
      }
      else
      {
        $l->warn( "Xmltv: Missing end-time for last entry for " .
                  "$chd->{xmltvid}_$date" );
      }
    }

    $self->close_writer( $w );
    $sth->finish();
  }

  # Create empty files for any dates that we haven't found any data for.
  foreach my $date (sort keys %dates)
  {
    if( $dates{$date} )
    {
      my $w = $self->create_writer( $chd->{xmltvid}, $date, $p );
      $self->close_writer( $w );
    }
  }
}

sub create_writer
{
  my $self = shift;
  my( $xmltvid, $date, $p ) = @_;

  my $path = $self->{Root};
  my $filename =  $xmltvid . "_" . $date . ".xml";

  $l->info( "Xmltv: $filename" );

  $self->{writer_filename} = $filename;
  $self->{writer_entries} = 0;

  my $fh = new IO::File "> $path$filename.new"
    or $l->logdie( "Xmltv: cannot write to $path$filename.new" );
  
  my $w = new XMLTV::Writer( encoding => 'ISO-8859-1',
                             OUTPUT   => $fh );
  
  $w->start({ 'generator-info-name' => 'nonametv' });
    
  return $w;
}

sub close_writer
{
  my $self = shift;
  my( $w ) = @_;

  my $path = $self->{Root};
  my $filename = $self->{writer_filename};
  delete $self->{writer_filename};

  $w->end();

  system("gzip -f -n $path$filename.new");
  if( -f "$path$filename.gz" )
  {
    system("diff $path$filename.new.gz $path$filename.gz > /dev/null");
    if( $? )
    {
      move( "$path$filename.new.gz", "$path$filename.gz" );
      $l->warn( "Exported $filename.gz" );
      if( $self->{writer_entries} == 0 )
      {
        $l->warn( "Xmltv: $filename.gz is empty" );
      }
      else
      {
        (xmltv_validate_file( "$path$filename.gz" ) == 0) 
          or $l->error( "Xmltv: $filename.gz contains errors\n" );
      }
    }
    else
    {
      unlink( "$path$filename.new.gz" );
    }
  }
  else
  {
    move( "$path$filename.new.gz", "$path$filename.gz" );
    $l->warn( "Xmltv: Exported $filename.gz" );
    ( xmltv_validate_file( "$path$filename.gz" ) == 0 )
      or $l->warn( "Xmltv: $filename.gz contains errors\n" );
  }
}

sub write_entry
{
  my $self = shift;
  my( $w, $data, $chd ) = @_;

  $self->{writer_entries}++;

  my $start_time = create_dt( $data->{start_time}, "UTC" );
  $start_time->set_time_zone( "Europe/Stockholm" );
  
  my $end_time = create_dt( $data->{end_time}, "UTC" );
  $end_time->set_time_zone( "Europe/Stockholm" );
  
  my $d = {
    channel => $chd->{xmltvid},
    start => $start_time->strftime( "%Y%m%d%H%M%S %z" ),
    stop => $end_time->strftime( "%Y%m%d%H%M%S %z" ),
    title => [ [ $data->{title}, $chd->{sched_lang} ] ],
  };
  
  $d->{desc} = [[ $data->{description},$chd->{sched_lang} ]] 
    if defined( $data->{description} ) and $data->{description} ne "";
  
  $d->{'sub-title'} = [[ $data->{subtitle}, $chd->{sched_lang} ]] 
    if defined( $data->{subtitle} ) and $data->{subtitle} ne "";
  
  if( defined( $data->{episode} ) and ($data->{episode} =~ /\S/) )
  {
    my( $season, $ep, $part ) = split( /\s*\.\s*/, $data->{episode} );
    if( $season =~ /\S/ )
    {
      $season++;
    }

    my( $ep_nr, $ep_max ) = split( "/", $ep );
    $ep_nr++;

    my $ep_text = "Del $ep_nr";
    $ep_text .= " av $ep_max" if defined $ep_max;
    $ep_text .= " säsong $season" if( $season );

    $d->{'episode-num'} = [[ $data->{episode}, 'xmltv_ns' ],
                           [ $ep_text, 'onscreen'] ];
  }
  
  if( defined( $data->{program_type} ) and ($data->{program_type} =~ /\S/) )
  {
    push @{$d->{category}}, [$data->{program_type}, 'en'];
  }
  elsif( defined( $chd->{def_pty} ) and ($chd->{def_pty} =~ /\S/) )
  {
    push @{$d->{category}}, [$chd->{def_pty}, 'en'];
  }

  if( defined( $data->{category} ) and ($data->{category} =~ /\S/) )
  {
    push @{$d->{category}}, [$data->{category}, 'en'];
  }
  elsif( defined( $chd->{def_cat} ) and ($chd->{def_cat} =~ /\S/) )
  {
    push @{$d->{category}}, [$chd->{def_cat}, 'en'];
  }

  if( defined( $data->{production_date} ) and 
      ($data->{production_date} =~ /\S/) )
  {
    $d->{date} = substr( $data->{production_date}, 0, 4 );
  }

  if( $data->{aspect} ne "unknown" )
  {
    $d->{video} = { aspect => $data->{aspect} };
  }

  if( $data->{directors} =~ /\S/ )
  {
    $d->{credits}->{director} = [split( ", ", $data->{directors})];
  }

  if( $data->{actors} =~ /\S/ )
  {
    $d->{credits}->{actor} = [split( ", ", $data->{actors})];
  }

  $w->write_programme( $d );
}

1;
