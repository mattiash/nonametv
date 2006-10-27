package NonameTV::Language;

=pod

Languages module for NonameTV.

=cut

use strict;
use warnings;

BEGIN 
{
  use Exporter   ();
  our (@ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
  
  @ISA         = qw(Exporter);
  @EXPORT      = qw( );
  %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
  @EXPORT_OK   = qw/LoadLanguage/;
}
our @EXPORT_OK;

sub LoadLanguage
{
  my( $lang, $module , $ds ) = @_;

  my $lng;

  my( $res, $sth ) = $ds->Sql( "SELECT * from lang_$lang WHERE module='$module'" );

  while( my $data = $sth->fetchrow_hashref() )
  {
    #print "$data->{strname} = $data->{strvalue}\n";

    $lng->{$data->{strname}} = $data->{strvalue};
  }

  return( $lng );
}

1;
