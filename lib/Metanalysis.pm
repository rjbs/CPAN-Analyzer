use 5.36.0;

package Metanalysis;
use Moose;

use DBI;
use version ();

has db_file => (
  is => 'ro',
  required => 1,
);

has dbh => (
  is => 'ro',
  lazy => 1,
  init_arg => undef,
  isa      => 'Object',
  default  => sub ($self) {
    DBI->connect('dbi:SQLite:dbname=' . $self->db_file, undef, undef);
  },
);

has perl_for_dist => (
  lazy      => 1,
  init_arg  => undef,
  traits    => [ 'Hash' ],
  handles   => { perl_for_dist => 'get' },
  builder   => '_build_perl_for_dist',
);

sub _build_perl_for_dist ($self) {
  my %perl_required;
  my $dbh = $self->dbh;

  my $rows = $dbh->selectall_arrayref(
    q{
      SELECT dist, requirements
      FROM dist_prereqs
      WHERE phase IN ('runtime', 'install', 'configure', 'build')
        AND module = 'perl'
    },
    { Slice => {} },
  );

  ROW: for my $row (@$rows) {
    my $perl_v = eval {
      version->parse($row->{requirements});
    };

    unless (defined $perl_v) {
      # warn "Skipping perl requirement for $row->{dist}: $row->{requirements}\n";

      next ROW;
    }

    next if $perl_required{$row->{dist}} && $perl_required{$row->{dist}} >= $perl_v;

    $perl_required{$row->{dist}} = $perl_v;
  }

  return \%perl_required;
}

1;
