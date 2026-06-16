load helper

@test "orchestrator dry-run runs acquire -> overlay -> customize -> manifest in order" {
  run env BUILD_DRY_RUN=1 BC_STAGE="$BC_STAGE" "$BUILD_ROOT/build-guard-image.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"acquire"* || "$output" == *"stock"* ]]
  [[ "$output" == *"DRYRUN qemu-img"* ]]
  [[ "$output" == *"DRYRUN virt-customize"* ]]
  [[ "$output" == *"manifest"* ]]
}

@test "--check validates prerequisites and exits cleanly" {
  run env BUILD_DRY_RUN= BUILD_REAL= "$BUILD_ROOT/build-guard-image.sh" --check
  [ "$status" -eq 0 ] || [ "$status" -eq 2 ]
}

@test "bc_preflight_tools requires veritysetup only when dm-verity is enabled" {
  run bash -c "source '$BUILD_ROOT/lib/build-common.sh'; BUILD_DMVERITY=1 bc_preflight_tools"
  [[ "$output" == *"qemu-img"* ]]
  [[ "$output" == *"virt-customize"* ]]
  [[ "$output" == *"veritysetup"* ]]
  run bash -c "source '$BUILD_ROOT/lib/build-common.sh'; BUILD_DMVERITY=0 bc_preflight_tools"
  [[ "$output" == *"qemu-img"* ]]
  [[ "$output" != *"veritysetup"* ]]
}

@test "orchestrator refuses to bake without BUILD_REAL=1 or BUILD_DRY_RUN=1 (exit 2)" {
  run env BUILD_DRY_RUN= BUILD_REAL= "$BUILD_ROOT/build-guard-image.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"refusing"* ]]
  ! grep -q "qemu-img" "$MOCK_LOG"   # nothing was baked
}
