#!/usr/bin/env perl
use 5.20.0;
use warnings;
use experimental 'postderef';
use List::Util 'sum0';
use Text::Table;

use Aggregate;

my $file   = $ARGV[0];
my $result = Aggregate->scan_file($file);
my $agg    = $ARGV[1] // 50;

Aggregate->aggregate_minorities($result, $agg);

my $dz_results = $result->{'Dist::Zilla'};
my $count      = $dz_results->{distfiles}->@*;
my $cpanids    = keys $dz_results->{cpanid}->%*;

printf "There are %s dists by %s unique cpan ids using Dist::Zilla.\n\n",
  $count,
  $cpanids;

my $table = Text::Table->new('generator', \' | ', 'dists', \' | ', \' | ', 'authors', '%');

my $total = sum0 map {; 0 + $_->{distfiles}->@* } values %$result;

for my $key (
  sort { $result->{$b}{distfiles}->@* <=> $result->{$a}{distfiles}->@* }
  keys %$result
) {
  my $count = $result->{$key}{distfiles}->@*;
  $table->add(
    $key,
    $count,
    scalar(keys $result->{$key}{cpanid}->%*),
    sprintf('%0.2f%%', $count/$total*100),
  );
}

print $table;
