package NonameTV::DataStore::Helper;

use strict;

use Carp;
use NonameTV::Log qw/info progress error logdie/;

=head1 NAME

NonameTV::DataStore::Helper

=head1 DESCRIPTION

Alternative interface to the datastore for NonameTV. Usable for Importers
that receive data where each programme entry does not contain a stop-time
and a date.

=head1 METHODS

=over 4

=cut

=item new

The constructor for the object. Called with a NonameTV::DataStore object
and a timezone-string as parameters. If the timezone is omitted, 
"Europe/Stockholm" is used.

=cut

sub new
{
  my $class = ref( $_[0] ) || $_[0];
  
  my $self = { }; 
  bless $self, $class;
  
  $self->{ds} = $_[1];
  $self->{timezone} = $_[2] || "Europe/Stockholm";
  
  return $self;
}

sub DESTROY
{
  my $self = shift;
  
}

=item StartBatch
  
  Called by an importer to signal the start of a batch of updates.
  Takes two parameters: one containing a string that uniquely identifies
  a set of programmes (a batch_id) and the channel_id for the channel
  that this data is for. The channel_id is a numeric index into the
  channels-table.
  
=cut

sub StartBatch
{
  my $self = shift;
  my( $batch_id, $channel_id ) = @_;
  
  $self->{batch_id} = $batch_id;
  $self->{channel_id} = $channel_id;

  $self->{lasttime} = undef;
  $self->{save_ce} = undef;
  $self->{curr_date} = undef;

  $self->{ds}->StartBatch( $batch_id );
}

=item EndBatch

Called by an importer to signal the end of a batch of updates.
Takes two parameters: 

An integer containing 1 if the batch was processed
successfully, 0 if the batch failed and the database should
be rolled back to the contents as they were before StartBatch was called.
and -1 if the batch should be rolled back because it has not changed.

A string containing a log-message to add to the batchrecord. If success==1,
then the log-message is stored in the field 'message'. If success==0, then
the log-message is stored in abort_message. If success==-1, the log message
is not stored. The log-message can be undef.

=cut

sub EndBatch
{
  my( $self, $success, $log ) = @_;

  $self->{ds}->EndBatch( $success, $log );
}

sub StartDate
{
  my $self = shift;
  my( $date, $time ) = @_;
  
#  print "StartDate: $date\n";
  my( $year, $month, $day ) = split( '-', $date );
  $self->{curr_date} = DateTime->new( 
                                      year   => $year,
                                      month  => $month,
                                      day    => $day,
                                      hour   => 0,
                                      minute => 0,
                                      second => 0,
                                      time_zone => $self->{timezone} );

  if( $self->{curr_date} < DateTime->today->subtract( days => 7 ) )
  {
    error( "$self->{batch_id}: StartDate called with old date, " .
           $self->{curr_date}->ymd("-") . "." );
  }
  if( defined( $time ) )
  {
    $self->{lasttime} = $self->create_dt( $self->{curr_date}, $time );
  }
  else
  {
    $self->{lasttime} = undef;
  }
    
}

=item AddProgramme

Called by an importer to add a programme for the current batch.
Takes a single parameter containing a hashref with information
about the programme. The hashref does NOT need to contain an end_time.

  $dsh->AddProgramme( {
    start_time  => "08:00",
    title       => "Morgon-tv",
    description => "Morgon i TV-soffan",
  } );

=cut

sub AddProgramme
{
  my $self = shift;
  my( $ce ) = @_;

#  print "AddProgramme: $ce->{start_time} $ce->{title}\n";

  if( not defined( $self->{curr_date} ) )
  {
    logdie( "Helper $self->{batch_id}: You must call StartDate before AddProgramme" );
  }

  my $start_time = $self->create_dt( $self->{curr_date}, 
                                     $ce->{start_time} );
  if( defined( $self->{lasttime} ) and ($start_time < $self->{lasttime}) )
  {
    $start_time->add( days => 1 );
    my $dur =  $start_time - $self->{lasttime};
    my( $days, $hours ) = $dur->in_units( 'days', 'hours' );
    $hours += $days*24;
    if( $hours > 20 )
    {
      error( "$self->{batch_id}: Improbable program start " . 
             $start_time->ymd . " " . $start_time->hms . " skipped" );
      return;
    }
    $self->{curr_date}->add( days => 1 );
  }
  $ce->{start_time} = $start_time->clone();

  $self->{lasttime} = $start_time->clone();

  if( defined( $ce->{end_time} ) )
  {
    my $stop_time = $self->create_dt( $self->{curr_date}, 
                                      $ce->{end_time} );
    if( $stop_time < $self->{lasttime} )
    {
      $stop_time->add( days => 1 );
      $self->{curr_date}->add( days => 1 );
    }
    $ce->{end_time} = $stop_time->clone();
    $self->{lasttime} = $stop_time->clone(); 
  }

  $self->AddCE( $ce );
}

sub AddCE
{
  my $self = shift;
  my( $ce ) = @_;

  $ce->{start_time}->set_time_zone( "UTC" );
  $ce->{start_time} = $ce->{start_time}->ymd('-') . " " . 
    $ce->{start_time}->hms(':');

  if( defined( $ce->{end_time} ) )
  {
    $ce->{end_time}->set_time_zone( "UTC" );
    $ce->{end_time} = $ce->{end_time}->ymd('-') . " " . 
	$ce->{end_time}->hms(':');
  }

  $ce->{channel_id} = $self->{channel_id};

  $self->{ds}->AddProgramme( $ce );
}

sub create_dt
{
  my $self = shift;
  my( $date, $time ) = @_;
  
#  print $date->ymd('-') . " $time\n";

  my $dt = $date->clone();
  
  my( $hour, $minute, $second ) = split( ":", $time );

  # Don't die for invalid times during shift to DST.
  my $res = eval {
    $dt->set( hour   => $hour,
              minute => $minute,
              );
  };

  if( not defined $res )
  {
    error( $self->{batch_id} . ": " . $dt->ymd('-') . " $hour:$minute: $@" );
    $hour++;
    error( "Adjusting to $hour:$minute" );
    $dt->set( hour   => $hour,
              minute => $minute,
              );
  }    
  
  return $dt;
}

1;
