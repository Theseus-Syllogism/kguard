load helper

@test "bc_acquire_stock downloads + verifies, idempotent" {
  source "$BUILD_ROOT/lib/build-common.sh"
  BUILD_DRY_RUN= bc_acquire_stock
  grep -q "curl" "$MOCK_LOG"
  grep -q "$(bc_kicksecure_url)" "$MOCK_LOG"
  grep -q "sha256sum" "$MOCK_LOG"
  [ -e "$(bc_stock_image)" ]
  : > "$MOCK_LOG"
  BUILD_DRY_RUN= bc_acquire_stock
  ! grep -q "curl" "$MOCK_LOG"
}

# Kicksecure's published .sha256 names the UPSTREAM file (e.g. Kicksecure-Xfce.qcow2), not our
# renamed kicksecure-stock.qcow2, so `sha256sum -c` fails on a missing filename. Verification must
# compare the digest value, filename-agnostic.
@test "bc_expected_hash extracts the digest regardless of the filename in the .sha256" {
  source "$BUILD_ROOT/lib/build-common.sh"
  h="3b1f8c4d2e6a7b9c0d1e2f3a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e"
  printf '%s  Kicksecure-Xfce.qcow2\n' "$h" > "$BATS_TEST_TMPDIR/s.sha256"
  run bc_expected_hash "$BATS_TEST_TMPDIR/s.sha256"
  [ "$status" -eq 0 ]
  [ "$output" = "$h" ]
}

@test "bc_expected_hash fails when the file carries no digest" {
  source "$BUILD_ROOT/lib/build-common.sh"
  printf 'no checksum here\n' > "$BATS_TEST_TMPDIR/bad.sha256"
  run bc_expected_hash "$BATS_TEST_TMPDIR/bad.sha256"
  [ "$status" -ne 0 ]
}
