#!/usr/bin/env perl
use v5.20.0;
use warnings;
use experimental 'postderef';

use Data::Dumper;

use Aggregate;
use Chart::Clicker;
use Chart::Clicker::Axis::DateTime;
use Chart::Clicker::Data::Series;
use Chart::Clicker::Data::DataSet;
use Date::Parse;

my $chart = Chart::Clicker->new; # build the chart

my @keys;
my %series;

for my $file (glob('*.csv'), glob('*.sqlite')) {
  my ($date) = $file =~ /(\d{4}.+?)\.(?:csv|sqlite)/;

  (my $key = $date) =~ s/-//g;

  my $result = Aggregate->scan_file($file);
  Aggregate->aggregate_minorities($result, 100);

  push @keys, $key;

  for my $tool (keys %$result) {
    $series{ $tool } ||= [];
    $series{ $tool }[ $#keys ] = @{ $result->{$tool}{distfiles} };

    $_ //= 0 for $series{ $tool }->@*;
  }
}

my @totals = (0) x @keys;;
for my $i (0 .. $#keys) {
  for my $set (keys %series) {
    $totals[ $i ] += $series{$set}[$i] // 0;
  }
}

for my $set (
  sort { $series{$b}[0] <=> $series{$a}[0] } keys %series
) {
  $#{ $series{$set} } = $#keys;

  next unless $set;

  $_ //= 0 for @{ $series{$set} };

  my $series = Chart::Clicker::Data::Series->new(
    name   => $set || '(blank)',
    keys   => [ map {; str2time($_) } @keys ],
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

$chart->get_context('default')->domain_axis(
  Chart::Clicker::Axis::DateTime->new(
    tick_label_angle => '5',
    orientation => 'horizontal',
    position    => 'bottom',
));

# write the chart to a file
$chart->write_output('chart.png');

