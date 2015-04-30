#!/usr/bin/env perl
use rjbs;

use DBI;
my $dbh = DBI->connect("dbi:SQLite:dbname=$ARGV[0]", undef, undef);

my %seen;

my $sth = $dbh->prepare(
  "SELECT DISTINCT module_dist
  FROM dist_prereqs
  WHERE dist = ?
    AND type = 'requires'
    AND phase <> 'develop'
    AND module_dist IS NOT NULL
  ORDER BY module_dist",
);

sub dump_prereqs ($dist, $indent) {
  my $rows = $dbh->selectall_arrayref(
    $sth,
    { Slice => {} },
    $dist,
  );

  for (@$rows) {
    printf "%s%s\n", ('  ' x $indent), $_->{module_dist};
    if ($seen{$_->{module_dist}}++) {
      # printf "%s%s\n", ('  ' x ($indent+1)), '<see above>';
    } else {
      dump_prereqs($_->{module_dist}, $indent+1);
    }
  }
}

dump_prereqs($ARGV[1], 0);
