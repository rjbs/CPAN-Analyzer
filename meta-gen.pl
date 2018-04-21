#!/usr/bin/env perl
use 5.20.0;
use warnings;
use Analyze;
use Getopt::Long::Descriptive;
use Ramdisk;

my ($opt, $desc) = describe_options(
  '%c %o',
  [ 'ramdisk', "make a ramdisk to which to extract" ],
);

my $cpan_root = "/Users/rjbs/minicpan";

my $ramdisk = $opt->ramdisk ? Ramdisk->new(1024) : undef;

Analyze->analyze_cpan({
  cpan_root => $cpan_root,
  ($ramdisk ? (work_root => $ramdisk->root) : ()),
});

