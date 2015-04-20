use 5.20.0;
use warnings;
use experimental 'postderef';
use List::Util 'sum0';
use Text::Table;

use Analyze;

my $result = Analyze->scan_file($ARGV[0]);
my $agg    = $ARGV[1] // 50;

Analyze->aggregate_minorities($result, $agg);

my $dz_results = $result->{'Dist::Zilla'};
my $count      = $dz_results->{distfiles}->@*;
my $authors    = keys $dz_results->{author}->%*;

printf "There are %s dists by %s unique authors using Dist::Zilla.\n\n",
  $count,
  $authors;

my $table = Text::Table->new('generator', \' | ', 'dists', \' | ', '%');

my $total = sum0 map {; 0 + $_->{distfiles}->@* } values %$result;

for my $key (
  sort { $result->{$b}{distfiles}->@* <=> $result->{$a}{distfiles}->@* }
  keys %$result
) {
  my $count = $result->{$key}{distfiles}->@*;
  $table->add($key, $count, sprintf('%0.2f%%', $count/$total*100));
}

print $table;
