use 5.20.0;
use warnings;
use experimental 'postderef';
package Analyze;

use DBI;
use Text::CSV_XS;
use Text::Table;

sub scan_db {
  my ($self, $filename) = @_;

  my $dsn = "dbi:SQLite:dbname=$filename";
  my $dbh = DBI->connect($dsn, undef, undef);

  my @cols = qw(
    distfile
    cpanid
    has_meta_yml has_meta_json meta_spec
    meta_generator meta_gen_package meta_gen_version meta_license
    meta_error
    has_dist_ini
  );

  my %tool;

  my $sth = $dbh->prepare("SELECT * FROM dists");
  $sth->execute;

  while (my $row = $sth->fetchrow_hashref) {
    my %hash;
    @hash{ @cols } = $row->@{ @cols };

    my $gen = $hash{meta_gen_package} // '';
    $gen = 'Dist::Zilla' if $gen =~ /Dist::Zilla/;
    my $tool = $tool{ $gen // $hash{meta_generator} // '' } ||= {};
    $tool->{distfiles} ||= [];
    push @{ $tool->{distfiles} }, $hash{distfile};
    $tool->{cpanid}{ $hash{cpanid} }++;
  }

  return \%tool;
}

sub scan_file {
  my ($self, $filename) = @_;

  my $csv = Text::CSV_XS->new;
  open my $fh, '<:encoding(utf8)', $filename or die "$filename: $!";

  my @cols = qw(
    distfile
    cpanid
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
    $gen = 'Dist::Zilla' if $gen eq 'Dist::Milla'; # cheating?
    my $tool = $tool{ $gen || $hash{meta_generator} } ||= {};
    $tool->{distfiles} ||= [];
    push @{ $tool->{distfiles} }, $hash{distfile};
    $tool->{cpanid}{ $hash{cpanid} }++;
  }

  return \%tool;
}

sub aggregate_minorities {
  my ($self, $input, $min_size) = @_;

  my %minority = (
    cpanid    => {},
    distfiles => [],
  );

  for my $key (keys %$input) {
    next if $input->{ $key }{distfiles}->@* >= $min_size;

    my $this = delete $input->{ $key };

    for my $cpanid (keys $this->{cpanid}->%*) {
      $minority{cpanid}{ $cpanid } += $this->{cpanid}{$cpanid};
    }

    push $minority{distfiles}->@*, $this->{distfiles}->@*;
  }

  $input->{__OTHER__} = \%minority;
}

1;
