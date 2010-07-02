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
  Analyze->aggregate_minorities($result, 50);

  push @keys, $key;

  for my $tool (keys %$result) {
    $series{ $tool } ||= [];
    $series{ $tool }[ $#keys ] = @{ $result->{$tool}{distfiles} };
  }
}

for my $set (keys %series) {
  $#{ $series{$set} } = $#keys;

  $_ //= 0 for @{ $series{$set} };

  my $series = Chart::Clicker::Data::Series->new(
    name   => $set,
    keys   => [ @keys ],
    values => [ @{ $series{ $set } } ],
  );

  # build the dataset
  my $dataset = Chart::Clicker::Data::DataSet->new(
    series => [ $series ],
  );

  # add the dataset to the chart
  $chart->add_to_datasets($dataset);
}

# write the chart to a file
$chart->write_output('chart.png');

