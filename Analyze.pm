use 5.12.0;
use warnings;
package Analyze;

use Moose::Autobox;
use Text::CSV_XS;
use Text::Table;

sub scan_file {
  my ($self, $filename) = @_;

  my $csv = Text::CSV_XS->new;
  open my $fh, '<:encoding(utf8)', $filename or die "$filename: $!";

  my @cols = qw(
    distfile
    author
    has_meta_yml has_meta_json meta_spec
    meta_generator meta_gen_package meta_gen_version meta_license
    meta_error
    has_dist_ini
  );

  my %tool;

  { my $headers = $csv->getline($fh) }

  while (my $row = $csv->getline($fh)) {
    my %hash;
    @hash{ @cols } = @$row;

    my $gen = $hash{meta_gen_package};
    $gen = 'Dist::Zilla' if $gen =~ /Dist::Zilla/;
    my $tool = $tool{ $gen || $hash{meta_generator} } ||= {};
    $tool->{distfiles} ||= [];
    push @{ $tool->{distfiles} }, $hash{distfile};
    $tool->{author}{ $hash{author} }++;
  }

  return \%tool;
}

sub aggregate_minorities {
  my ($self, $input, $min_size) = @_;

  my %minority = (
    author    => {},
    distfiles => [],
  );

  for my $key (keys %$input) {
    next if $input->{ $key }{distfiles}->length >= $min_size;

    my $this = delete $input->{ $key };

    $this->{author}->each(sub { $minority{author}{$_[0]} += $_[1] });
    $minority{distfiles}->push( $this->{distfiles}->flatten );
  }

  $input->{__OTHER__} = \%minority;
}

1;
