use 5.12.0;
use CPAN::Visitor;
use Date::Format;
use DBI;
use JSON;
use Parse::CPAN::Meta;
use YAML::Tiny;

my $visitor = CPAN::Visitor->new(cpan => "/Users/rjbs/Sync/minicpan");
my $count   = $visitor->select;

my $JSON = JSON->new;

printf "preparing to scan %s files...\n", $count;

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

$visitor->iterate(
  jobs  => 12,
  visit => sub {
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

    my $dbh = DBI->connect(
      "dbi:SQLite:dbname=$filename", q{}, q{},
      { RaiseError => 1 },
    );
    if (my $meta = $json_distmeta || $yaml_distmeta) {
      $dist{meta_spec} = eval { $meta->{'meta-spec'}{version} };
      $dist{meta_generator} = $meta->{generated_by};

    $dbh->do("PRAGMA synchronous = OFF");
      if ($meta->{generated_by} =~ /\A(\S+) version ([^\s,]+)/) {
        $dist{meta_gen_package} = $1;
        $dist{meta_gen_version} = $2;
      }

      $dist{meta_license} = $meta->{license} // '';
    }

    my $hooks = join q{, }, ('?') x @cols;
    $dbh->do("INSERT INTO dists VALUES ($hooks)", undef, @dist{@cols});
    say "completed $dist{distfile} (mtime $dist{mtime})";
  }
);

