# shellcheck shell=bash
setup() {
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export KGUARD_HOME="$BATS_TEST_TMPDIR/home"
  export KGUARD_STAGE="$BATS_TEST_TMPDIR/stage"
  mkdir -p "$KGUARD_HOME" "$KGUARD_STAGE"
  # fake guard image so existence checks pass
  : > "$KGUARD_STAGE/kicksecure-guard.qcow2"
  export KGUARD_IMG="$KGUARD_STAGE/kicksecure-guard.qcow2"
  export MOCK_LOG="$BATS_TEST_TMPDIR/mock.log"; : > "$MOCK_LOG"
  chmod +x "$PROJECT_ROOT/tests/mock/"*
  export PATH="$PROJECT_ROOT/tests/mock:$PATH"
  export KGUARD_SETPASS_STDIN=1
  export KGUARD_STOP_TIMEOUT=2   # keep the stop wait-loop short in tests
  # Source common helpers so test bodies can call kg_* functions directly
  # (e.g. kg_keyfile in test 6 of qemu_args.bats) and so KGUARD_MEM is
  # visible for grep -qx assertions.
  source "$PROJECT_ROOT/lib/kguard-common.sh"
  export KGUARD_MEM
}
