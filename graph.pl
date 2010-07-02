use strict;
use warnings;

use Data::Dumper;

use Analyze;
use Chart::Clicker;
use Chart::Clicker::Data::Series;
use Chart::Clicker::Data::DataSet;

my $chart = Chart::Clicker->new; # build the chart

my @keys;
my %series;

for my $file (glob('*.csv')) {
  my ($date) = $file =~ /(\d{4}.+?)\.csv/;

  (my $key = $date) =~ s/-//g;

  my $result = Analyze->scan_file($file);
  Analyze->aggregate_minorities($result, 100);

  push @keys, $key;

  for my $tool (keys %$result) {
    $series{ $tool } ||= [];
    $series{ $tool }[ $#keys ] = @{ $result->{$tool}{distfiles} };
  }
}

my @totals;
for my $i (0 .. $#keys) {
  for my $set (keys %series) {
    $totals[ $i ] += $series{$set}[$i];
  }
}

use Data::Dumper;
warn Dumper(\@totals);

for my $set (
  sort { $series{$b}[0] <=> $series{$a}[0] } keys %series
) {
  $#{ $series{$set} } = $#keys;

  $_ //= 0 for @{ $series{$set} };

  my $series = Chart::Clicker::Data::Series->new(
    name   => $set || '(blank)',
    keys   => [ @keys ],
    values => [ map { $series{$set}[$_] / $totals[$_] * 100 } (0..$#keys) ],
  );

  # build the dataset
  my $dataset = Chart::Clicker::Data::DataSet->new(
    series => [ $series ],
  );

  warn "adding $set\n";

  # add the dataset to the chart
  $chart->add_to_datasets($dataset);
}

$chart->get_context('default')->range_axis->range(
  Chart::Clicker::Data::Range->new(lower => 0, upper => 50)
);

# write the chart to a file
$chart->write_output('chart.png');

