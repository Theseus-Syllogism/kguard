load helper

@test "install creates kguard + kguard-setpass symlinks in target bindir" {
  bindir="$BATS_TEST_TMPDIR/bin"; mkdir -p "$bindir"
  KGUARD_BINDIR="$bindir" "$PROJECT_ROOT/install.sh"
  [ -L "$bindir/kguard" ]
  [ -L "$bindir/kguard-setpass" ]
  [ "$(readlink "$bindir/kguard")" = "$PROJECT_ROOT/bin/kguard" ]
  [ -x "$PROJECT_ROOT/bin/kguard" ]
}
