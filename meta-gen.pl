use 5.12.0;
use CPAN::Visitor;
use Date::Format;
use DBI;
use YAML::Tiny;

my $visitor = CPAN::Visitor->new(cpan => "/Users/rjbs/Sync/minicpan");
my $count   = $visitor->select;

printf "preparing to scan %s files...\n", $count;

my $total = 0;
my @data;

my $filename = sprintf('dist-%s.sqlite', time2str('%Y-%m-%d', time));
my $dbh      = DBI->connect("dbi:SQLite:dbname=$filename", q{}, q{},
                            { RaiseError => 1 });

$dbh->do("CREATE TABLE dists (
  distfile PRIMARY KEY,
  author,
  has_meta_yml,
  has_meta_json,
  meta_spec,
  meta_generator,
  meta_gen_package,
  meta_gen_version,
  meta_license,
  meta_error,
  has_dist_ini
)");

my @cols = qw(
  distfile author has_meta_yml has_meta_json meta_spec meta_generator
  meta_gen_package meta_gen_version meta_license meta_error has_dist_ini
);

my %template = map {; $_ => '' } @cols;

$visitor->iterate(
  jobs  => 10,
  visit => sub {
    my ($job) = @_;

    my %dist = %template;
    $dist{has_meta_yml}  = -e 'META.yml'  ? 1 : 0;
    $dist{has_meta_json} = -e 'META.json' ? 1 : 0;
    $dist{has_dist_ini}  = -e 'dist.ini'  ? 1 : 0;

    $dist{distfile} = $job->{distfile};
    ($dist{author}) = split m{/}, $job->{distfile};

    if ($dist{has_meta_yml}) {
      my ($data) = eval {
        my $out = YAML::Tiny->read('META.yml');
        return $out->[0] if $out;
        die YAML::Tiny->errstr;
      };

      if ($data) {
        $dist{meta_spec} = eval { $data->{'meta-spec'}{version} };
        $dist{meta_generator} = $data->{generated_by};

        if ($data->{generated_by} =~ /(\S+) version (\S+)/) {
          $dist{meta_gen_package} = $1;
          $dist{meta_gen_version} = $2;
        }

        $dist{meta_license} = $data->{license} // '';
      } else {
        my $error = $@;
        ($error) = split m{$}m, $error;
        $dist{meta_error} = $error;
      }
    }

    my $hooks = join q{, }, ('?') x @cols;
    $dbh->do("INSERT INTO dists VALUES ($hooks)", undef, @dist{@cols});
    say "completed $dist{distfile}";
  }
);

