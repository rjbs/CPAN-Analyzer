use 5.36.0;

package Ramdisk;

use Process::Status;

sub new ($class, $size_in_mb) {
  state $i = 1;

  my $dev  = $class->_mk_ramdev($size_in_mb);
  my $type = q{Case-sensitive HFS+};
  my $name = sprintf "ramdisk-%s-%05u-%u", $^T, $$, $i++;

  system(qw(diskutil eraseVolume), $type, $name, $dev)
    and die "couldn't create fs on $dev: " . Process::Status->as_string;

  my $guts = {
    root => "/Volumes/$name",
    size => $size_in_mb,
    dev  => $dev,
    pid  => $$,
  };

  return bless $guts, $class;
}

sub root ($self) { $self->{root} }
sub size ($self) { $self->{size} }
sub dev  ($self) { $self->{dev}  }

sub DESTROY ($self) {
  return unless $$ == $self->{pid};
  system(qw(diskutil eject), $self->dev)
    and warn "couldn't unmount $self->{root}: " . Process::Status->as_string;
}

sub _mk_ramdev ($class, $size_in_mb) {
  my $size_arg = $size_in_mb * 2048;
  my $dev  = `hdiutil attach -nomount ram://$size_arg`;

  chomp $dev;
  $dev =~ s/\s+\z//;

  return $dev;
}

1;
