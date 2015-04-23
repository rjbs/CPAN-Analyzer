use 5.20.0;
use experimental 'postderef';
use CPAN::Meta;
use CPAN::Visitor;
use Date::Format;
use DBI;
use JSON;
use Parallel::ForkManager;
use Parse::CPAN::Meta;
use Parse::CPAN::Packages::Fast;

my $cpan_root = "/Users/rjbs/Sync/minicpan";

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
  dist,
  cpanid,
  mtime INTEGER,
  has_meta_yml,
  has_meta_json,
  meta_spec,
  meta_generator,
  meta_gen_package,
  meta_gen_version,
  meta_license,
  meta_yml_error,
  meta_yml_backend,
  meta_json_error,
  meta_json_backend,
  meta_struct_error,
  has_dist_ini
)");

$dbh->do(
  "CREATE TABLE dist_prereqs (dist, phase, type, module, requirements, module_dist)",
);

my @cols = qw(
  distfile dist cpanid mtime has_meta_yml has_meta_json meta_spec meta_generator
  meta_gen_package meta_gen_version meta_license
  meta_yml_error meta_yml_backend meta_json_error meta_yml_backend
  meta_struct_error
  has_dist_ini
);

my %template = map {; $_ => undef } @cols;

my $pm = Parallel::ForkManager->new(10);

$pm->run_on_finish(sub {
  my ($pid, $exit_code, $ident) = @_;
  die "pid $pid exited non-zero\n" if $exit_code;
});

my $index = Parse::CPAN::Packages::Fast->new(
  "$cpan_root/modules/02packages.details.txt.gz"
);

my @dists = $index->latest_distributions;
my $total = @dists;
my %dist_object;

my %dist_for_pkg = $index->{pkg_to_dist}->%*;
$dist_for_pkg{$_} = CPAN::DistnameInfo->new($dist_for_pkg{$_})->dist
  for keys %dist_for_pkg;

while (my @next = splice @dists, 0, 250) {
  $pm->start and next;

  my @files;

  for my $item (@next) {
    $dist_object{join '/', $item->cpanid, $item->filename} = $item;
    push @files, $item->pathname =~ s/^.....//r;
  }

  my $visitor = CPAN::Visitor->new(
    cpan  => $cpan_root,
    files => \@files,
    stash => { prefer_bin => 1 },
  );

  printf "starting a child with %s elements; %s remain\n",
    0+@next, 0+@dists;

  my $dbh = DBI->connect(
    "dbi:SQLite:dbname=$filename", q{}, q{},
    { RaiseError => 1 },
  );

  $dbh->do("PRAGMA synchronous = OFF");

  $visitor->iterate(
    jobs     => 1,
    visit    => process_job($dbh),
    check    => sub { return -e $_[0]->{distpath} },
    enter    => sub {
      my ($job) = @_;
      my $dir = $job->{result}{extract};
      my $perm = (stat $dir)[2] & 07777;
      chmod($perm | 0100, $dir) unless $perm & 0100;
      goto &CPAN::Visitor::_enter;
    },
  );

  $pm->finish;
}

$pm->wait_all_children;

sub process_job {
  my ($dbh) = @_;

  return sub {
    my ($job) = @_;

    my %report = %template;
    my $dist = $dist_object{ $job->{distfile} };

    $report{dist} = $dist->dist;

    $report{distfile} = $job->{distfile};
    ($report{cpanid}) = split m{/}, $job->{distfile};

    $report{has_meta_yml}  = -e 'META.yml'  ? 1 : 0;
    $report{has_meta_json} = -e 'META.json' ? 1 : 0;
    $report{has_dist_ini}  = -e 'dist.ini'  ? 1 : 0;

    $report{mtime} = (stat $job->{distpath})[9];

    my $json_distmeta;
    my $yaml_distmeta;

    if ($report{has_meta_yml}) {
      $report{meta_yml_error} = $@ || '(unknown error)' unless eval {
        $yaml_distmeta = Parse::CPAN::Meta->load_file('META.yml'); 1;
      };

      $report{meta_yml_backend} = $yaml_distmeta->{x_serialization_backend}
        if $yaml_distmeta;
    }

    if ($report{has_meta_json}) {
      $report{meta_json_error} = $@ || '(unknown error)' unless eval {
        $json_distmeta = Parse::CPAN::Meta->load_file('META.json'); 1
      };

      $report{meta_json_backend} = $json_distmeta->{x_serialization_backend}
        if $json_distmeta;
    }

    if (my $meta = $json_distmeta || $yaml_distmeta) {
      $report{meta_spec} = eval { $meta->{'meta-spec'}{version} };
      $report{meta_generator} = $meta->{generated_by};

      if ($meta->{generated_by} =~ /\A(\S+) version ([^\s,]+)/) {
        $report{meta_gen_package} = $1;
        $report{meta_gen_version} = $2;
      }

      $report{meta_license} = $meta->{license} // '';
      $report{meta_license} = join q{, }, $report{meta_license}->@*
        if ref $report{meta_license};

      my $meta_obj;
      $report{meta_struct_error} = $@ || '(unknown error)' unless eval {
        $meta_obj = CPAN::Meta->new($meta);
      };

      if ($meta_obj) {
        my $prereqs = $meta_obj->effective_prereqs->as_string_hash;
        for my $phase (keys $prereqs->%*) {
          for my $type (keys $prereqs->{$phase}->%*) {
            for my $module (keys $prereqs->{$phase}{$type}->%*) {
              $dbh->do(
                "INSERT INTO dist_prereqs (dist, phase, type, module, requirements, module_dist)
                VALUES (?, ?, ?, ?, ?, ?)",
                undef,
                $dist->dist, $phase, $type, $module, $prereqs->{$phase}{$type}{$module},
                $dist_for_pkg{$module},
              );
            }
          }
        }
      }
    }

    my $hooks = join q{, }, ('?') x @cols;
    $dbh->do("INSERT INTO dists VALUES ($hooks)", undef, @report{@cols});

    # printf "completed $report{distfile}\n";
  }
}
