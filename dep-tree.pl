#!/usr/bin/env perl
use rjbs;

use DBI;
use Getopt::Long::Descriptive;
use Term::ANSIColor;

my ($opt, $usage) = describe_options(
  '%c %o DBFILE DIST [TARGET-DIST]',
  [ 'prune=s@', 'stop if you hit this path on the way to a target' ],
);

my ($dbfile, $dist, $to_dist) = @ARGV;

my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", undef, undef);

my %seen;

my $sth = $dbh->prepare(
  "SELECT DISTINCT module_dist
  FROM dist_prereqs
  WHERE dist = ?
    AND type = 'requires'
    AND phase <> 'develop'
    AND module_dist IS NOT NULL
  ORDER BY LOWER(module_dist)",
);

sub dump_prereqs ($dist, $indent) {
  my $rows = $dbh->selectall_arrayref(
    $sth,
    { Slice => {} },
    $dist,
  );

  for (@$rows) {
    if ($seen{$_->{module_dist}}++) {
      print color('green');
      printf "%s%s\n", ('  ' x $indent), $_->{module_dist};
      print color('reset');
      # printf "%s%s\n", ('  ' x ($indent+1)), '<see above>';
    } else {
      print color('bold green');
      printf "%s%s\n", ('  ' x $indent), $_->{module_dist};
      print color('reset');
      dump_prereqs($_->{module_dist}, $indent+1);
    }
  }
}

sub _dists_required_by ($dist) {
  my $rows = $dbh->selectall_arrayref(
    $sth,
    { Slice => {} },
    $dist,
  );

  return map {; $_->{module_dist} } $rows->@*;
}

my %PATH_FOR;
sub _paths_between ($dist, $target, $path = []) {
  return $PATH_FOR{ $dist, $target } if exists $PATH_FOR{ $dist, $target };

  return $PATH_FOR{ $dist, $target } = $target if $dist eq $target;
  return $PATH_FOR{ $dist, $target } = undef if grep {; $_ eq $dist } @{ $opt->prune || [] };
  return $PATH_FOR{ $dist, $target } = undef unless my @prereqs = _dists_required_by($dist);

  my %in_path = map {; $_ => 1 } @$path;

  my %return;
  for my $prereq ( grep { ! $in_path{$_} } @prereqs ) {
    my $paths = _paths_between($prereq, $target, [ @$path, $prereq ]);
    $return{$prereq} = $paths if $paths;
  }

  return $PATH_FOR{ $dist, $target } = keys %return ? \%return : undef;
}

sub print_tree ($tree, $depth = 0) {
  my $leader = '  ' x $depth;

  unless (ref $tree) {
    print "$leader$tree\n";
    return;
  }

  for my $key (sort { fc $a cmp fc $b } keys %$tree) {
    my $value = $tree->{$key};
    my $mark  = ref $value ? "" : "* ";

    print "$leader$mark$key\n";
    print_tree($tree->{$key}, $depth+1) if ref $value;
  }
}

if ($to_dist) {
  if (my $tree = _paths_between($dist, $to_dist)) {
    print_tree($tree);
  } else {
    print "no path from $dist to $to_dist\n";
  }
} else {
  dump_prereqs($dist, 0);
}
