package NonameTV::DataStore;

use strict;

use NonameTV qw/FixProgrammeData/;
use NonameTV::Log qw/info progress error logdie/;
use Carp qw/confess/;
use UTF8DBI;

use Storable qw/dclone/;
use Encode qw/decode_utf8/;

use utf8;

=head1 NAME

NonameTV::DataStore

=head1 DESCRIPTION

Interface to the datastore for NonameTV. The datastore is normally
an SQL database, but the interface for this class makes no
assumption about it.

=head1 METHODS

=over 4

=cut

=item new

The constructor for the object. Called with a hashref as the only parameter.
This is a ref to the configuration for the object from the nonametv.conf-
file.

The configuration must contain the following keys:

type

"MySQL" is currently the only allowed type.

dbhost, dbname, username, password

Specifies how to connect to the MySQL database.

=cut

sub new
{
  my $class = ref( $_[0] ) || $_[0];

  my $self = { }; 
  bless $self, $class;

  # Copy the parameters supplied in the constructor.
  foreach my $key (keys(%{$_[1]}))
  {
      $self->{$key} = ($_[1])->{$key};
  }

  defined( $self->{type} ) and $self->{type} eq "MySQL" 
    or die "type must be MySQL: $self->{type}";

  defined( $self->{dbhost} ) or die "You must specify dbhost";
  defined( $self->{dbname} ) or die "You must specify dbname";
  defined( $self->{username} ) or die "You must specify username";
  defined( $self->{password} ) or die "You must specify password";

  my $host = $self->{dbhost};
  my $database = $self->{dbname};
  my $driver = 'mysql';
  
  my $dsn = "DBI:$driver:database=$database;host=$host";
  
  $self->{dbh} = UTF8DBI->connect($dsn, $self->{username}, $self->{password})
      or die "Cannot connect: " . $DBI::errstr;


  $self->{dbh}->do("set character set utf8");
  $self->{dbh}->do("set names utf8");

  $self->{SILENCE_END_START_OVERLAP} = 0;
  $self->{SILENCE_DUPLICATE_SKIP} = 0;

  return $self;
}

sub DESTROY
{
  my $self = shift;

  $self->{dbh}->disconnect() 
    if defined( $self->{dbh} );
}

=item Creating a new batch

To create a new batch or replace an old batch completely, 
do the following steps:

  StartBatch( $batch_id );
  AddProgramme( ... );
  AddProgramme( ... );
  ...
  EndBatch( $success, $message );

=item StartBatch

Called by an importer to signal the start of a batch of updates.
Takes a single parameter containing a string that uniquely identifies
a set of programmes.  

=cut

sub StartBatch
{
  my( $self, $batchname ) = @_;

  confess( "Nested calls to StartBatch" )
    if( defined( $self->{currbatch} ) );
  
  my $id = $self->Lookup( 'batches', { name => $batchname }, 'id' );

  if( defined( $id ) )
  {
    $self->DoSql( "START TRANSACTION" );
    $self->Delete( 'programs', { batch_id => $id } );
  }
  else
  {
    $id = $self->Add( 'batches', { name => $batchname } );
    $self->DoSql( "START TRANSACTION" );
  }
    
  $self->{last_start} = "1970-01-01 00:00:00";
  $self->{last_prog} = undef;

  $self->SetBatch( $id, $batchname );
}

# Hidden method used internally and by DataStore::Updater.
sub SetBatch
{
  my $self = shift;
  my( $id, $batchname ) = @_;

  $self->{currbatch} = $id;
  $self->{currbatchname} = $batchname;
  $self->{batcherror} = 0;
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
  
  confess( "EndBatch called without StartBatch" )
    unless defined( $self->{currbatch} );
  
  $log = "" if not defined $log;

  $self->AddLastProgramme( undef );

  if( $success == 0 or $self->{batcherror} )
  {
    $self->DoSql("Rollback");
    error( $self->{currbatchname} . ": Rolling back changes" );

    if( defined( $log ) )
    {
      $self->Update( 'batches', { id => $self->{currbatch} },
                     { abort_message => $log } );
    }
  }
  elsif( $success==1 )
  {
    $self->Update( 'batches', { id => $self->{currbatch} }, 
                   { last_update => time(),
                     message => $log,
                     abort_message => "",
                   } );

    $self->DoSql("Commit");
  }
  elsif( $success == -1 )
  {
    $self->DoSql("Rollback");
  }
  else
  {
    confess( "Wrong value for success" );
  }

  delete $self->{currbatch};
}


=item AddProgramme

Called by an importer to add a programme for the current batch.
Takes a single parameter contining a hashref with information
about the programme.

  $ds->AddProgramme( {
    channel_id => 1,
    start_time => "2004-12-24 14:00:00",
    end_time   => "2004-12-24 15:00:00", # Optional
    title      => "Kalle Anka och hans vänner",
    subtitle   => "Episode title"        # Optional
    description => "Traditionsenligt julfirande",
    episode    =>  "0 . 12/13 . 0/3", # Season, episode and part as xmltv_ns
                                      # Optional
    category   => [ "sport" ],        # Optional
  } );

The times must be in UTC. The strings must be encoded in iso-8859-1.

=cut

sub AddProgramme
{
  my( $self, $data ) = @_;

  logdie( "You must call StartBatch before AddProgramme" ) 
    unless exists $self->{currbatch};

  return if $self->{batcherror};
  
  if( ( $data->{start_time} eq $self->{last_start} )
      and ($data->{title} = $self->{last_title} ) )
  {
    error( $self->{currbatchname} . 
           "Skipping duplicate entry for $data->{start_time}" )
      unless $self->{SILENCE_DUPLICATE_SKIP};
    return
  }
  elsif( $data->{start_time} le $self->{last_start} )
  {
    error( $self->{currbatchname} . 
      ": Starttime must be later than last starttime: " . 
      $self->{last_start} . " -> " . $data->{start_time} );
    return;
  }

  $self->AddLastProgramme( $data->{start_time} );

  $self->{last_start} = $data->{start_time};
  $self->{last_title} = $data->{title};

  if( $data->{title} eq 'end-of-transmission' )
  {
    # We have already added all the necessary info with the call to
    # AddLastProgramme. Do not add an explicit entry for end-of-transmission
    # since this might collide with the start of tomorrows shows.
    return;
  }


  if( exists( $data->{end_time} ) )
  {
    if( $data->{start_time} ge $data->{end_time} )
    {
      error( $self->{currbatchname} . 
	  ": Stoptime must be later than starttime: " . 
	  $data->{start_time} . " -> " . $data->{end_time} );
      return;
    }
  }

  FixProgrammeData( $data );

  $self->{last_prog} = dclone( $data );
}

sub AddLastProgramme
{
  my $self = shift;
  my( $nextstart ) = @_;

  my $data = $self->{last_prog};
  return if not defined $data;

  if( defined( $nextstart ) )
  {
    if( defined( $data->{end_time} ) )
    {
      if( $nextstart lt $data->{end_time} )
      {
        error( $self->{currbatchname} . 
               " Starttime must be later than or equal to last endtime: " . 
               $data->{end_time} . " -> " . $nextstart ) 
          unless $self->{SILENCE_END_START_OVERLAP};

        $data->{end_time} = $nextstart;
      }
    }
    else
    {
      $data->{end_time} = $nextstart;
    }
  }

  $self->AddProgrammeRaw( $data );
  $self->{last_prog} = undef;
}

=item AddProgrammeRaw

Same as AddProgramme but does not check for overlapping programmes or
require that the programmes are added in order.

=cut

sub AddProgrammeRaw
{
  my( $self, $data ) = @_;
  
  logdie( "You must call StartBatch before AddProgramme" ) 
    unless exists $self->{currbatch};

  return if $self->{batcherror};
  
  if( $data->{title} !~ /\S/ )
  {
    error( $self->{currbatchname} . ": Empty title at " . $data->{start_time} );
    $data->{title} = "end-of-transmission";
  }

  $data->{batch_id} = $self->{currbatch};

  if( not defined( $data->{category} ) )
  {
    delete( $data->{category} );
  }

  if( not defined( $data->{program_type} ) )
  {
    delete( $data->{program_type} );
  }

  
  if( exists( $data->{description} ) and defined( $data->{description} ) )
  {
    # Strip leading and trailing whitespace from description.
    $data->{description} =~ s/^\s+//;
    $data->{description} =~ s/\s+$//;
  }

  if( $self->Add( 'programs', $data, 0 ) == -1 )
  {
    my $err = $self->{dbh_errstr};

    # Check for common error-conditions
    my $data_org = $self->Lookup( "programs", 
                                  { 
                                    channel_id => $data->{channel_id},
                                    start_time => $data->{start_time}
                                  }
                                  );

    if( defined( $data_org ) )
    {
      if( $data_org->{title} eq "end-of-transmission" )
      {
        error( $self->{currbatchname} . ": Replacing end-of-transmission " .
               "for $data->{channel_id}-$data->{start_time}" );

        $self->Delete( "programs", 
                                  { 
                                    channel_id => $data->{channel_id},
                                    start_time => $data->{start_time}
                                  }
                       );

        if( $self->Add( 'programs', $data, 0 ) == -1 )
        {
          error( $self->{currbatchname} . ": " . $self->{dbh}->errstr );
          $self->{batcherror} = 1;
        }
      }
      elsif( $data_org->{title} eq $data->{title} )
      {
        error( $self->{currbatchname} . ": Skipping duplicate entry " .
               "for $data->{channel_id}-$data->{start_time}" ) 
          unless $self->{SILENCE_DUPLICATE_SKIP};
      }
      else
      {
        error( $self->{currbatchname} . ": Duplicate programs " .
               $data->{start_time} . ": '" . $data->{title} . "', '" . 
               $data_org->{title} . "'" );
        $self->{batcherror} = 1;
      }
    }
    else
    {
      error( $self->{currbatchname} . ": $err" );
      $self->{batcherror} = 1;
    }
  }
}

=item LookupCat

Lookup a category found in an infile and translate it to
a proper program_type and category for use in AddProgramme.

  my( $pty, $cat ) = $ds->LookupCat( 'Viasat', 'MUSIK' );
  $ds->AddProgramme( { ..., category => $cat, program_type => $pty } );

=cut

sub LookupCat
{
  my $self = shift;
  my( $type, $org ) = @_;

  return (undef, undef) if (not defined( $org )) or ($org !~ /\S/);

  $org =~ s/^\s+//;
  $org =~ s/\s+$//;

  # I should be using locales, but I don't dare turn them on.
  $org = lc( $org );
  $org =~ tr/ÅÄÖ/åäö/;

  $self->LoadCategories()
    if not exists( $self->{categories} );

  
  if( not exists( $self->{categories}->{"$type++$org"} ) )
  {
    # MySQL considers some characters as equal, e.g. e and é.
    # Trying to insert both anime and animé will give an error-message
    # from MySql. Therefore, I try to lookup the new entry before adding
    # it to see if MySQL thinks it already exists. I should probably
    # normalize the strings before inserting them instead...
    my $data = $self->Lookup( "trans_cat", 
                              { type => $type, original => $org } );
    if( defined( $data ) )
    {
      $self->{categories}->{ $type . "++" . $org}
        = [$data->{program_type}, $data->{category} ];
    }
    else
    {
      $self->AddCategory( $type, $org );
    }
  }

  if( defined( $self->{categories}->{"$type++$org"} ) )
  {
    return @{($self->{categories}->{"$type++$org"})};
  }
  else
  {
    return (undef,undef);
  }
        
}

sub LoadCategories
{
  my $self = shift;

  my $d = {};

  my $sth = $self->Iterate( 'trans_cat', {} );
  if( not defined( $sth ) )
  {
    $self->{categories} = {};
    error( "No categories found in database." );
    return;
  }

  while( my $data = $sth->fetchrow_hashref() )
  {
    $d->{$data->{type} . "++" . $data->{original}} = [$data->{program_type},
                                                      $data->{category} ];
  }
  $sth->finish();

  $self->{categories} = $d;
}

sub AddCategory
{
  my $self = shift;
  my( $type, $org ) = @_;

  $self->Add( 'trans_cat', { type => $type,
                             original => $org } );
  $self->{categories}->{"$type++$org"} = [undef,undef];
}

=back 

=head1 SQL-like interface

TBD. Should this interface really be public?

=cut

=over 4

=item Count( $table, $args )

Return the number of records in table $table matching $args. $table should
be a string containing the name of a table, $args should be a hash-reference
with field-names and values.

=cut

sub Count
{
  my $self = shift;
  my( $table, $args ) = @_;

  my $dbh=$self->{dbh};

  my @where = ("(1)");
  my @values = ();

  map { push @where, "($_ = ?)"; push @values, $args->{$_}; }
      sort keys %{$args};

  my $where = join " and ", @where;
  my $sql = "select count(*) from $table where $where";

  my $sth = $dbh->prepare( $sql )
      or die "Prepare failed. $sql\nError: " . $dbh->errstr;

  $sth->execute( @values ) 
      or die "Execute failed. $sql\nError: " . $dbh->errstr;

  my $aref=$sth->fetchrow_arrayref;
  my $res=$aref->[0];
  $sth->finish;
  return $res;
}

=item Delete( $table, $args )

Delete all records in table $table matching $args. $table should
be a string containing the name of a table, $args should be a hash-reference
with field-names and values. Returns the number of deleted records.

=cut

sub Delete
{
  my $self = shift;
  my( $table, $args ) = @_;

  my $dbh=$self->{dbh};

  my @where = ("(1)");
  my @values = ();

  map { push @where, "($_ = ?)"; push @values, $args->{$_}; }
      sort keys %{$args};

  my $where = join " and ", @where;
  my $sql = "delete from $table where $where";

  my $sth = $dbh->prepare_cached( $sql )
      or die "Prepare failed. $sql\nError: " . $dbh->errstr;

  my $res = $sth->execute( @values );
  $sth->finish;

  return $res;
}

=item Add( $table, $values, $die_on_error )

Add a new record to a table. $table should be a string containing the name 
of a table, $values should be a hash-reference with field-names and values.
$die_on_error defaults to 1.
Returns the primary key assigned to the new record or -1 if the Add failed.

=cut 

sub Add
{
  my $self = shift;
  my( $table, $args, $die_on_error ) = @_;

  $die_on_error = 1 unless defined( $die_on_error );

  my $dbh=$self->{dbh};

  my @fields = ();
  my @values = ();

  map { push @fields, "$_ = ?"; push @values, $args->{$_}; }
      sort keys %{$args};

  my $fields = join ", ", @fields;
  my $sql = "insert into $table set $fields";

  my $sth = $dbh->prepare_cached( $sql )
      or die "Prepare failed. $sql\nError: " . $dbh->errstr;

  $sth->{PrintError} = 0;

  if( not $sth->execute( @values ) )
  {
    if( $die_on_error ) 
    {
      die "Execute failed. $sql\nError: " . $dbh->errstr;
    }
    else
    {
      $self->{dbh_errstr} = $dbh->errstr;
      $sth->finish();
      return -1;
    }
  }
  
  $sth->finish();

  return $sth->{'mysql_insertid'};
}

=item Update( $table, $args, $new_values )

Update all records matching $args. $table should be a string containing the name of a table, $args and $new_values should be a hash-reference with field-names and values. Returns the number of updated records.

Example:
    $ds->Update( "users", { uid => 1 }, 
		 { lastname => "Holmlund", 
		   firstname => "Mattias" } );

=cut

sub Update
{
  my $self = shift;
  my( $table, $args, $new_values ) = @_;

  my $dbh=$self->{dbh};

  my @where = ("(1)");
  my @values = ();

  map { push @where, "($_ = ?)"; push @values, $args->{$_}; }
      sort keys %{$args};

  my $where = join " and ", @where;

  my @set = ();
  my @setvalues = ();
  map { push @set, "$_ = ?"; push @setvalues, $new_values->{$_}; }
      sort keys %{$new_values};

  my $setexpr = join ", ", @set;

  my $sql = "UPDATE $table SET $setexpr WHERE $where";

  my $sth = $dbh->prepare( $sql )
      or die "Prepare failed. $sql\nError: " . $dbh->errstr;

  my $res = $sth->execute( @setvalues, @values ) 
      or die "Execute failed. $sql\nError: " . $dbh->errstr;

  $sth->finish();

  return $res;
}

=item Lookup( $table, $args [, $field] )

Retrieve values from a record. $table should be a string containing the name 
of a table, $args should be a hash-reference with field-names and values. 
If $field is specified, it should be the name of a field in the record and
Lookup will then return the contents of that field. If $field is undef, 
a hash-reference with all fields and values in the record is returned.

If $args fails to identify one unique record, undef is returned. 

=cut

sub Lookup
{
  my $self = shift;
  my( $table, $args, $field ) = @_;

  my $dbh=$self->{dbh};

  my @where = ("(1)");
  my @values = ();

  map { push @where, "($_ = ?)"; push @values, $args->{$_}; }
      sort keys %{$args};

  my $where = join " and ", @where;

  my $sql;

  if( defined $field )
  {
    $sql = "SELECT $field FROM $table WHERE $where";
  }
  else
  {
    $sql = "SELECT * FROM $table WHERE $where";
  }

  my $sth = $dbh->prepare_cached( $sql )
      or die "Prepare failed. $sql\nError: " . $dbh->errstr;

  my $res = $sth->execute( @values ) 
      or die "Execute failed. $sql\nError: " . $dbh->errstr;
  
  if( $res == 0 )
  {
    $sth->finish();
    return undef;
  }

  die "More than one record returned by $sql (" . join( ", ", @values) . ")"
      if( $res > 1 );

  my $row = $sth->fetchrow_hashref;

  
  $sth->finish();

  return $row->{$field} if defined $field;
  return $row;
}

=item Iterate

Same as Lookup, but returns a dbi statement handle that can be used
as an iterator. Can also take several field-arguments.

=cut 

sub Iterate
{
  my $self = shift;
  my( $table, $args, @fields ) = @_;

  my $dbh=$self->{dbh};

  my @where = ("(1)");
  my @values = ();

  map { push @where, "($_ = ?)"; push @values, $args->{$_}; }
      sort keys %{$args};

  my $where = join " and ", @where;

  my $sql;

  if( scalar( @fields ) > 0 )
  {
    $sql = "SELECT " . join(",", @fields ) . " FROM $table WHERE $where";
  }
  else
  {
    $sql = "SELECT * FROM $table WHERE $where";
  }

  my $sth = $dbh->prepare( $sql )
      or die "Prepare failed. $sql\nError: " . $dbh->errstr;

  my $res = $sth->execute( @values ) 
      or die "Execute failed. $sql\nError: " . $dbh->errstr;
  
  return undef if $res == 0;

  return $sth;
}

sub Sql
{
  my $self = shift;
  my( $sqlexpr, $values ) = @_;

  my $dbh=$self->{dbh};

  my $sth = $dbh->prepare( $sqlexpr )
      or die "Prepare failed. $sqlexpr\nError: " . $dbh->errstr;

  my $res = $sth->execute( @{$values} ) 
      or die "Execute failed. $sqlexpr\nError: " . $dbh->errstr;

  return ($res, $sth);
}

sub DoSql
{
  my $self = shift;
  my( $sqlexpr, $values ) = @_;

  my( $res, $sth ) = $self->Sql( $sqlexpr, $values );

  $sth->finish();
}

=head1 COPYRIGHT

Copyright (C) 2004 Mattias Holmlund.

=cut

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
