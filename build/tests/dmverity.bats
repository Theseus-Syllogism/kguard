load helper

@test "bc_dmverity_setup computes a verity hashtree and records the root hash (dry-run)" {
  run bash -c "source '$BUILD_ROOT/lib/build-common.sh'; BUILD_DRY_RUN=1 bc_dmverity_setup '$BC_STAGE/img.qcow2'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"veritysetup"* ]]
}

@test "dm-verity is skippable with BUILD_DMVERITY=0" {
  run bash -c "source '$BUILD_ROOT/lib/build-common.sh'; BUILD_DMVERITY=0 bc_dmverity_setup '$BC_STAGE/img.qcow2'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip"* ]]
}
