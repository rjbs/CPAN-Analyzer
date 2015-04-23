use 5.20.0;
use warnings;
package Ramdisk;
use Process::Status;

sub new {
  my ($class, $mb) = @_;

  state $i = 1;

  my $dev  = $class->_mk_ramdev($mb);
  my $type = q{Case-sensitive Journaled HFS+};
  my $name = sprintf "ramdisk-%s-%05u-%u", $^T, $$, $i++;

  system(qw(diskutil eraseVolume), $type, $name, $dev)
    and die "couldn't create fs on $dev: " . Process::Status->as_string;

  my $guts = {
    root => "/Volumes/$name",
    size => $mb,
    dev  => $dev,
    pid  => $$,
  };

  return bless $guts, $class;
}

sub root { $_[0]{root} }
sub size { $_[0]{size} }
sub dev  { $_[0]{dev}  }

sub DESTROY {
  return unless $$ == $_[0]{pid};
  system(qw(diskutil eject), $_[0]->dev)
    and warn "couldn't unmount $_[0]{root}: " . Process::Status->as_string;
}

sub _mk_ramdev {
  my ($class, $mb) = @_;

  my $size_arg = $mb * 2048;
  my $dev  = `hdiutil attach -nomount ram://$size_arg`;

  chomp $dev;
  $dev =~ s/\s+\z//;

  return $dev;
}

1;
