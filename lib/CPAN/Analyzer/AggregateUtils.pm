use 5.36.0;

package CPAN::Analyzer::AggregateUtils;

sub scan_db_file ($self, $filename) {
  require DBI;
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

  my $sth = $dbh->prepare("SELECT * FROM dists");
  $sth->execute;

  return $self->_process_iterator(sub {
    return unless my $row = $sth->fetchrow_hashref;
    my %hash;
    @hash{ @cols } = $row->@{ @cols };
    return \%hash;
  });
}

sub _process_iterator ($self, $iterator) {
  my %tool;

  while (my $row = $iterator->()) {
    my $gen = $row->{meta_gen_package} // $row->{meta_generator} // '';
    $gen = 'Dist::Zilla' if $gen =~ /\ADist::Zilla./;

    my $tool = $tool{ $gen } ||= {};
    $tool->{distfiles} ||= [];
    push @{ $tool->{distfiles} }, $row->{distfile};

    unless (defined $row->{cpanid}) {
      # What the heck happened?! -- rjbs, 2018-04-21
      my ($cpanid) = split m{/}, $row->{distfile};
      $row->{cpanid} = $cpanid;
    }

    $tool->{cpanid}{ $row->{cpanid} }++;
  }

  return \%tool;
}

sub aggregate_minorities ($self, $input, $min_size) {
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
