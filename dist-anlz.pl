use 5.12.0;
use warnings;
use Text::Table;

use Analyze;

my $result = Analyze->scan_file($ARGV[0]);
my $agg    = $ARGV[1] // 50;

Analyze->aggregate_minorities($result, $agg);

my $dz_results = $result->{'Dist::Zilla'};
my $count   = @{ $dz_results->{distfiles} };
my $authors = keys %{ $dz_results->{author} };

printf "There are %s dists by %s unique authors using Dist::Zilla.\n\n",
  $count,
  $authors;

my $table = Text::Table->new('generator', \' | ', 'dists');

$table->add($_, scalar @{ $result->{$_}{distfiles} }) for
  sort { @{ $result->{$b}{distfiles} } <=> @{ $result->{$a}{distfiles} } }
  keys %$result;

print $table;
