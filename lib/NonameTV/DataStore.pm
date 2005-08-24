package NonameTV::DataStore;

use strict;

use NonameTV::Log qw/info progress error logdie/;
use Carp qw/croak/;
use DBI;

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
  
  $self->{dbh} = DBI->connect($dsn, $self->{username}, $self->{password})
      or die "Cannot connect: " . $DBI::errstr;

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

  croak( "Nested calls to StartBatch" )
    if( defined( $self->{currbatch} ) );
  
  $self->DoSql( "START TRANSACTION" );
  my $id = $self->Lookup( 'batches', { name => $batchname }, 'id' );
  if( defined( $id ) )
  {
    $self->Delete( 'programs', { batch_id => $id } );
  }
  else
  {
    $id = $self->Add( 'batches', { name => $batchname } );
  }
    
  $self->{last_end} = "1970-01-01 00:00:00";
  $self->{last_start} = "1970-01-01 00:00:00";

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
successfully and 0 if the batch failed and the database should
be rolled back to the contents as they were before StartBatch was called.

A string containing a log-message to add to the batchrecord. If success==1,
then the log-message is stored in the field 'message'. If success==0, then
the log-message is stored in abort_message. The log-message can be undef.

=cut

sub EndBatch
{
  my( $self, $success, $log ) = @_;
  
  croak( "EndBatch called without StartBatch" )
    unless defined( $self->{currbatch} );
  
  $log = "" if not defined $log;

  if( $success and not $self->{batcherror} )
  {
    $self->Update( 'batches', { id => $self->{currbatch} }, 
                   { last_update => time(),
                     message => $log } );

    $self->DoSql("Commit");
  }
  else
  {
    $self->DoSql("Rollback");
    error( $self->{currbatchname} . ": Rolling back changes" );

    if( defined( $log ) )
    {
      $self->Update( 'batches', { id => $self->{currbatch} },
                     { abort_message => $log } );
    }
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
  
  if( $data->{start_time} le $self->{last_start} )
  {
    error( $self->{currbatchname} . 
      ": Starttime must be later than last starttime: " . 
      $self->{last_start} . " -> " . $data->{start_time} );
    return;
  }

  if( defined( $self->{last_end} ) and 
      ($self->{last_end} gt $data->{start_time}) )
  {
    error( $self->{currbatchname} . 
      " Starttime must be later than or equal to last endtime: " . 
      $self->{last_end} . " -> " . $data->{start_time} );
    
    # Add the programme anyway and let the exporter sort it out.
  }

  $self->{last_start} = $data->{start_time};
  $self->{last_end} = undef;

  if( exists( $data->{end_time} ) )
  {
    if( $data->{start_time} ge $data->{end_time} )
    {
      error( $self->{currbatchname} . 
	  ": Stoptime must be later than starttime: " . 
	  $data->{start_time} . " -> " . $data->{end_time} );
      return;
    }
    $self->{last_end} = $data->{end_time};
  }

  fix_programme_data( $data );

  $self->AddProgrammeRaw( $data );
}

=item AddProgrammeRaw

Same as AddProgramme but doesn't check for overlapping programmes or
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

  eval {
    $self->Add( 'programs', $data );
  };

  if( $@ )
  {
    error( $self->{currbatchname} . ": " . $@ );
    $self->{batcherror} = 1;
  }
}

sub fix_programme_data
{
  my( $d ) = @_;

  $d->{title} =~ s/^s.songs+tart\s*:*\s*//gi;
  $d->{title} =~ s/^seriestart\s*:*\s*//gi;
  $d->{title} =~ s/^reprisstart\s*:*\s*//gi;
  $d->{title} =~ s/^programstart\s*:*\s*//gi;

  $d->{title} =~ s/^s.songs*avslutning\s*:*\s*//gi;
  $d->{title} =~ s/^sista\s+delen\s*:*\s*//gi;

  if( $d->{title} =~ s/^((matin.)|(fredagsbio))\s*:\s*//gi )
  {
    $d->{program_type} = 'movie';
    $d->{category} = 'Movies';
  }

  # Set program_type to series if the entry has an episode-number
  # but doesn't have a program_type.
  if( exists( $d->{episode} ) and defined( $d->{episode} ) and
      ( (not defined($d->{program_type})) or ($d->{program_type} =~ /^\s*$/) ) )
  {
    $d->{program_type} = "series";
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

  $self->AddCategory( $type, $org )
    if not exists( $self->{categories}->{"$type++$org"} );

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

=item Add( $table, $values )

Add a new record to a table. $table should be a string containing the name 
of a table, $values should be a hash-reference with field-names and values.
Returns the primary key assigned to the new record.

=cut 

sub Add
{
  my $self = shift;
  my( $table, $args ) = @_;

  my $dbh=$self->{dbh};

  my @fields = ();
  my @values = ();

  map { push @fields, "$_ = ?"; push @values, $args->{$_}; }
      sort keys %{$args};

  my $fields = join ", ", @fields;
  my $sql = "insert into $table set $fields";

  my $sth = $dbh->prepare_cached( $sql )
      or die "Prepare failed. $sql\nError: " . $dbh->errstr;

  $sth->execute( @values ) 
      or die "Execute failed. $sql\nError: " . $dbh->errstr;

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
