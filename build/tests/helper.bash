# shellcheck shell=bash
setup_file() {
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export BUILD_ROOT="$PROJECT_ROOT/build"
}
setup() {
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  BUILD_ROOT="$PROJECT_ROOT/build"
  export BUILD_ROOT
  export BC_STAGE="$BATS_TEST_TMPDIR/stage"; mkdir -p "$BC_STAGE"
  export MOCK_LOG="$BATS_TEST_TMPDIR/mock.log"; : > "$MOCK_LOG"
  chmod +x "$BUILD_ROOT/tests/mock/"*
  export PATH="$BUILD_ROOT/tests/mock:$PATH"
  export BUILD_DRY_RUN=1
}
