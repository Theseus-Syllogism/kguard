load helper

@test "pinned versions and output naming" {
  source "$BUILD_ROOT/lib/build-common.sh"
  [ "$(bc_suricata_version)" = "8.0.4" ]
  [ -n "$(bc_kicksecure_url)" ]
  [ "$(bc_guard_version)" != "" ]
  [ "$(bc_out_image)" = "$BC_STAGE/kicksecure-guard-$(bc_guard_version).qcow2" ]
  [ "$(bc_manifest_path)" = "$(bc_out_image).manifest.json" ]
}

@test "bc_log writes to stderr, not stdout" {
  source "$BUILD_ROOT/lib/build-common.sh"
  run bash -c "source '$BUILD_ROOT/lib/build-common.sh'; bc_log hi 2>/dev/null"
  [ -z "$output" ]
}
