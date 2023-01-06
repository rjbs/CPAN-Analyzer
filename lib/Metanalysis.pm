use 5.36.0;

package Metanalysis;
use Moose;

use DBI;
use Path::Tiny;
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
      WHERE phase IN ('runtime', 'install', 'configure', 'build', 'test')
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

has cpan_root => (
  is    => 'ro',
  lazy  => 1,
  default => sub ($self) {
    confess "no cpan_root provided and no \$HOME" unless $ENV{HOME};

    my $root = "$ENV{HOME}/minicpan";

    confess "no cpan_root provided and no $root"
      unless -d $root;

    return $root;
  },
);

# Okay, so this is a bit mehhhh because what we care about is dist permissions,
# which aren't exactly a thing, but I *think* that for some years now, any dist
# X-Z will have a matching X::Z module existing for it.  Thanks, younger rjbs!
has module_permissions => (
  lazy => 1,
  reader  => '_perms',
  default => sub ($self) {
    my $root  = path($self->cpan_root);
    my $perms = $root->child(qw( modules 06perms.txt ));

    my @perms_lines = $perms->lines;
    chomp @perms_lines;

    my %perm;
    for my $line (@perms_lines) {
      next unless $line =~ /,[a-z]\z/;
      my ($pm, $owner, $type) = split /,/, $line;

      $perm{$pm}{$owner} = $type;
    }

    \%perm;
  }
);

sub first_come ($self, $dist) {
  my $module = $dist =~ s/-/::/gr;
  my $perms = $self->_perms->{$module};

  return unless $perms;

  my ($first) = grep {; $perms->{$_} eq 'f' } keys $perms->{$module}->%*;
  return $first;
}

sub maintainers ($self, $dist) {
  my $module = $dist =~ s/-/::/gr;
  my $perms = $self->_perms->{$module};

  return unless $perms;
  return keys %$perms;
}

sub maximum_perl_required_among ($self, $dists) {
  my @consider = grep {; $_ ne 'podlators' } @$dists; # podlators is weird
  my @perls = grep {; defined }
              map  {; $self->perl_for_dist($_) }
              @consider;

  my ($max) = sort {; $b <=> $a } @perls;

  state $v5_10 = version->parse('v5.10');

  if ($ENV{DEBUG}) {
    my @at_v5_10 = grep {; $self->perl_for_dist($_) == $v5_10 } @consider;
    if (@at_v5_10) {
      say "v5.10 via @at_v5_10";
    }
  }

  return $max;
}

# Valid arguments:
#   * phases: arrayref; phases of prereq to include
#   * types : arrayref; types of prereqs to include; default to [ requires ]
sub recursive_requirements_for ($self, $root, $arg = {}) {
  my $dbh = $self->dbh;

  my $i = 0;
  my %seen  = ($root => $i);
  my @queue = ($root);

  my $phases = $arg->{phases} // [ qw(build configure install runtime test)];
  my $types  = $arg->{types}  // [ qw(requires) ];

  my $phase_hooks = join q{, }, ('?') x @$phases;
  my $type_hooks  = join q{, }, ('?') x @$types;

  my $sth = $dbh->prepare(
    "SELECT DISTINCT module_dist
    FROM dist_prereqs
    WHERE dist = ?
      AND phase IN ($phase_hooks)
      AND type IN ($type_hooks)
      AND module_dist IS NOT NULL
      AND module_dist <> 'perl'
    ORDER BY LOWER(module_dist)",
  );

  while (@queue) {
    my @this = @queue;
    @queue = ();

    for my $dist (@this) {
      my $prereqs = $dbh->selectcol_arrayref($sth, undef, $dist, @$phases, @$types);

      for my $prereq (@$prereqs) {
        next if exists $seen{$prereq};
        $seen{$prereq} = $i;
        push @queue, $prereq;
      }
    }

    $i++;
  }

  return keys %seen;
}


1;
