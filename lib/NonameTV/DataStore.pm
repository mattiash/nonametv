package NonameTV::DataStore;

use strict;

use Carp;
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

  $self->{dbh}->disconnect();
}

=item StartBatch

Called by an importer to signal the start of a batch of updates.
Takes a single parameter containing a string that uniquely identifies
a set of programmes.  

=cut

sub StartBatch
{
  my( $self, $batchname ) = @_;
  
  my $id = $self->Lookup( 'batches', { name => $batchname }, 'id' );
  if( defined( $id ) )
  {
    $self->Delete( 'programs', { batch_id => $id } );
  }
  else
  {
    $id = $self->Add( 'batches', { name => $batchname } );
  }
    
  $self->{currbatch} = $id;
}

=item EndBatch

Called by an importer to signal the end of a batch of updates.
Takes a single parameter containing 1 if the batch was received
successfully and 0 if the batch failed and the database should
be rolled back to the contents as they were before StartBatch was called.

=cut

sub EndBatch
{
  my( $self, $success ) = @_;
  
  $self->Update( 'batches', { id => $self->{currbatch} }, 
               { last_update => time() } );

  delete $self->{currbatch};
}


=item AddProgramme

Called by an importer to add a programme for the current batch.
Takes a single parameter contining a hashref with information
about the programme.

=cut

sub AddProgramme
{
  my( $self, $data ) = @_;
  
  die "You must call StartBatch before AddProgramme" 
    unless exists $self->{currbatch};

  $self->Add( 'programs',
              {
                channel_id  => $data->{channel_id},
                start_time  => $data->{start_time},
                end_time    => $data->{end_time},
                title       => $data->{title},
                description => $data->{description},
                episode_nr  => $data->{episode_nr},
                season_nr   => $data->{season_nr},
                batch_id    => $self->{currbatch},
              }
              );
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


=head1 COPYRIGHT

Copyright (C) 2004 Mattias Holmlund.

=cut

1;
