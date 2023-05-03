use 5.36.0;

package Analyze;

use CPAN::Meta;
use CPAN::Visitor;
use Date::Format;
use DBI;
use JSON::XS;
use Parallel::ForkManager;
use Parse::CPAN::Meta;
use Parse::CPAN::Packages::Fast;
use Path::Tiny;

sub analyze_cpan ($self, $arg) {
  my $cpan_root = $arg->{cpan_root};
  $arg->{work_root} && (local $ENV{TMPDIR} = $arg->{work_root});

  my $JSON = JSON::XS->new;

  my @data;

  my $filename = sprintf '%s/dist-%s.sqlite',
    $ENV{PWD},
    time2str('%Y-%m-%d', time);

  my $dbh      = DBI->connect("dbi:SQLite:dbname=$filename", q{}, q{},
                              { RaiseError => 1 });

  $dbh->do("CREATE TABLE dists (
    distfile PRIMARY KEY,
    dist,
    dist_version,
    cpanid,
    mtime INTEGER,
    mdatetime,
    is_tarbomb INTEGER,
    file_count INTEGER,
    has_meta_yml INTEGER,
    has_meta_json INTEGER,
    meta_spec,
    meta_dist_version,
    meta_generator,
    meta_gen_package,
    meta_gen_version,
    meta_gen_perl,
    meta_license,
    meta_yml_error,
    meta_yml_backend,
    meta_json_error,
    meta_json_backend,
    meta_struct_error,
    meta_provides_defined INTEGER,
    has_makefile_pl INTEGER,
    has_build_pl INTEGER,
    has_dist_ini INTEGER
  )");

  $dbh->do(
    "CREATE TABLE dist_prereqs (dist, phase, type, module, requirements, module_dist)",
  );

  $dbh->do(
    "CREATE INDEX dist_prereqs_by_dist on dist_prereqs (dist, phase, type)",
  );

  $dbh->do(
    "CREATE INDEX dist_prereqs_by_target on dist_prereqs (module_dist, phase, type)",
  );

  my @cols = qw(
    distfile dist dist_version cpanid mtime mdatetime is_tarbomb file_count
    has_meta_yml has_meta_json meta_spec
    meta_dist_version
    meta_generator
    meta_gen_package meta_gen_version meta_gen_perl
    meta_license
    meta_yml_error meta_yml_backend meta_json_error meta_yml_backend
    meta_struct_error
    meta_provides_defined
    has_makefile_pl has_build_pl has_dist_ini
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
  my %dist_object;

  # XXX: Violating encapsulation here!
  my %dist_for_pkg = $index->{pkg_to_dist}->%*;
  $dist_for_pkg{$_} = CPAN::DistnameInfo->new($dist_for_pkg{$_})->dist
    for keys %dist_for_pkg;

  while (my @next = splice @dists, 0, (@dists % 250 || 250)) {
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
      visit    => process_job($dbh, {
        cols         => \@cols,
        dist_object  => \%dist_object,
        dist_for_pkg => \%dist_for_pkg,
        template     => \%template,
      }),
      check    => sub { return -e $_[0]->{distpath} },
      enter    => sub {
        my ($job) = @_;
        my $dir = $job->{result}{extract};
        my $perm = (stat $dir)[2] & 07777;
        chmod($perm | 0100, $dir) unless $perm & 0100;
        # XXX: Violating encapsulation here!
        goto &CPAN::Visitor::_enter;
      },
    );

    $pm->finish;
  }

  $pm->wait_all_children;
}

sub process_job ($dbh, $state) {
  return sub ($job) {
    my %report = $state->{template}->%*;
    my $dist = $state->{dist_object}{ $job->{distfile} };

    {
      # If the cwd is the job's tempdir, the tarball was badly behaved.
      # If the cwd's parent is the job's tempdir, the tarball was nicely behaved.
      # Otherwise, WTF is going on?
      my $cwd     = Path::Tiny->cwd;
      my $job_dir = path($job->{tempdir})->absolute;
      my $parent  = $cwd->parent->absolute;

      $cwd    =~ s{\A/private}{};
      $parent =~ s{\A/private}{};

      if ($job_dir eq $cwd) {
        $report{is_tarbomb} = 1;
        # die "$job->{distfile} is badly behaved!\n";
      } elsif ($job_dir eq $parent) {
        $report{is_tarbomb} = 0;
        # warn "$job->{distfile} is nicely behaved!\n";
      } else {
        $report{is_tarbomb} = 2;
        # warn "$job->{distfile} is a mystery!\n";
      }
    }

    my @files = `find . -type f`;
    $report{file_count}   = @files;

    $report{dist}         = $dist->dist;
    $report{dist_version} = $dist->version;

    $report{distfile} = $job->{distfile};
    ($report{cpanid}) = split m{/}, $job->{distfile};

    $report{has_meta_yml}     = -e 'META.yml'     ? 1 : 0;
    $report{has_meta_json}    = -e 'META.json'    ? 1 : 0;
    $report{has_makefile_pl}  = -e 'Makefile.PL'  ? 1 : 0;
    $report{has_build_pl}     = -e 'Build.PL'     ? 1 : 0;
    $report{has_dist_ini}     = -e 'dist.ini'     ? 1 : 0;

    $report{meta_provides_defined} = 0;

    $report{mtime}      = (stat $job->{distpath})[9];
    $report{mdatetime}  = time2str('%Y-%m-%d %X', $report{mtime});

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
      $report{meta_generator}     = $meta->{generated_by};
      $report{meta_dist_version}  = $meta->{version};

      if (($meta->{generated_by}//'') =~ m{\A(\S+?) version ([^\s,]+)}) {
        $report{meta_gen_package} = $1;
        $report{meta_gen_version} = $2;
      } elsif (($meta->{generated_by}//'') =~ m{\A(\S+)/([^\s,]+)}) {
        $report{meta_gen_package} = $1;
        $report{meta_gen_version} = $2;
      }

      if ($meta->{x_generated_by_perl}) {
        $report{meta_gen_perl} = $meta->{x_generated_by_perl};
      } elsif ($meta->{x_Dist_Zilla}) {
        $report{meta_gen_perl} = version
                                  ->parse($meta->{x_Dist_Zilla}{perl}{version})
                                  ->normal;
      }

      $report{meta_license} = $meta->{license} // '';
      $report{meta_license} = join q{, }, $report{meta_license}->@*
        if ref $report{meta_license};

      my $meta_obj;
      $report{meta_struct_error} = $@ || '(unknown error)' unless eval {
        $meta_obj = CPAN::Meta->new($meta);
      };

      if ($meta_obj) {
        $report{meta_provides_defined} = 1 if $meta_obj->provides->%*;

        my $prereqs = $meta_obj->effective_prereqs->as_string_hash;
        for my $phase (keys $prereqs->%*) {
          for my $type (keys $prereqs->{$phase}->%*) {
            for my $module (keys $prereqs->{$phase}{$type}->%*) {
              $dbh->do(
                "INSERT INTO dist_prereqs (dist, phase, type, module, requirements, module_dist)
                VALUES (?, ?, ?, ?, ?, ?)",
                undef,
                $dist->dist, $phase, $type, $module, $prereqs->{$phase}{$type}{$module},
                $state->{dist_for_pkg}{$module},
              );
            }
          }
        }
      }
    }

    my $hooks = join q{, }, ('?') x $state->{cols}->@*;
    $dbh->do("INSERT INTO dists VALUES ($hooks)", undef, @report{ $state->{cols}->@* });

    # printf "completed $report{distfile}\n";
  }
}

1;
