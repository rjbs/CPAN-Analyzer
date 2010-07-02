use 5.12.0;
use CPAN::Visitor;
use Date::Format;
use Text::CSV_XS;
use YAML::Tiny;

my $visitor = CPAN::Visitor->new(cpan => "/Users/rjbs/mirrors/minicpan");
my $count   = $visitor->select;

printf "preparing to scan %s files...\n", $count;

my $csv   = Text::CSV_XS->new;
my $total = 0;
my @data;

$csv->eol("\n");

my $filename = sprintf('dist-%s.csv', time2str('%Y-%m-%d', time));
open my $csv_fh, ">:encoding(utf8)", $filename or die "$filename: $!";

my @cols = qw(
  distfile
  author
  has_meta_yml has_meta_json meta_spec
  meta_generator meta_gen_package meta_gen_version meta_license
  meta_error
  has_dist_ini
);

$csv->print($csv_fh, \@cols);

my %template = map {; $_ => '' } @cols;

$visitor->iterate(
  visit => sub {
    my ($job) = @_;
    $total++;

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

    $csv->print($csv_fh, [ @dist{ @cols } ]);
    say "completed $total / $count";
  }
);

close $csv_fh or die "error closing $filename: $!";

