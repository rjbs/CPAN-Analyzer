use 5.20.0;
use experimental 'postderef';
use CPAN::Visitor;
use Date::Format;
use DBI;
use JSON;
use Parallel::ForkManager;
use Parse::CPAN::Meta;

my $JSON = JSON->new;

my $total = 0;
my @data;

my $filename = sprintf '%s/dist-%s.sqlite',
  $ENV{PWD},
  time2str('%Y-%m-%d', time);

my $dbh      = DBI->connect("dbi:SQLite:dbname=$filename", q{}, q{},
                            { RaiseError => 1 });

$dbh->do("CREATE TABLE dists (
  distfile PRIMARY KEY,
  author,
  mtime INTEGER,
  has_meta_yml,
  has_meta_json,
  meta_spec,
  meta_generator,
  meta_gen_package,
  meta_gen_version,
  meta_license,
  meta_yml_error,
  meta_json_error,
  has_dist_ini
)");

my @cols = qw(
  distfile author mtime has_meta_yml has_meta_json meta_spec meta_generator
  meta_gen_package meta_gen_version meta_license meta_yml_error meta_json_error
  has_dist_ini
);

my %template = map {; $_ => undef } @cols;

my $pm = Parallel::ForkManager->new(10);

my $visitor = CPAN::Visitor->new(cpan => "/Users/rjbs/Sync/minicpan");
my $count   = $visitor->select;

while (@{ $visitor->{files} }) {
  my @next = splice @{ $visitor->{files} }, 0, 250;
  printf "starting a child with %s elements; %s remain\n",
    0+@next, 0+@{ $visitor->{files} };

  $pm->start and next;

  $visitor->{files} = \@next;

  my $dbh = DBI->connect(
    "dbi:SQLite:dbname=$filename", q{}, q{},
    { RaiseError => 1, sqlite_use_immediate_transaction => 1 },
  );

  $dbh->do("PRAGMA synchronous = OFF");

  $visitor->iterate(
    jobs     => 1,
    visit    => process_job($dbh),
  );

  $pm->finish;
}

$pm->wait_all_children;

sub process_job {
  my ($dbh) = @_;

  return sub {
    my ($job) = @_;

    my %dist = %template;
    $dist{has_meta_yml}  = -e 'META.yml'  ? 1 : 0;
    $dist{has_meta_json} = -e 'META.json' ? 1 : 0;
    $dist{has_dist_ini}  = -e 'dist.ini'  ? 1 : 0;

    $dist{mtime} = (stat $job->{distpath})[9];

    $dist{distfile} = $job->{distfile};
    ($dist{author}) = split m{/}, $job->{distfile};

    my $json_distmeta;
    my $yaml_distmeta;

    if ($dist{has_meta_yml}) {
      $dist{meta_yml_error} = $@ || '(unknown error)' unless eval {
        $yaml_distmeta = Parse::CPAN::Meta->load_file('META.yml'); 1;
      };
    }

    if ($dist{has_meta_json}) {
      $dist{meta_json_error} = $@ || '(unknown error)' unless eval {
        $json_distmeta = Parse::CPAN::Meta->load_file('META.json'); 1
      };
    }

    if (my $meta = $json_distmeta || $yaml_distmeta) {
      $dist{meta_spec} = eval { $meta->{'meta-spec'}{version} };
      $dist{meta_generator} = $meta->{generated_by};

      if ($meta->{generated_by} =~ /\A(\S+) version ([^\s,]+)/) {
        $dist{meta_gen_package} = $1;
        $dist{meta_gen_version} = $2;
      }

      $dist{meta_license} = $meta->{license} // '';
    }

    my $hooks = join q{, }, ('?') x @cols;
    $dbh->do("INSERT INTO dists VALUES ($hooks)", undef, @dist{@cols});

    printf "completed $dist{distfile}\n";
  }
}
