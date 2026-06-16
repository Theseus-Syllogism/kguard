load helper

# Opt-in real bake. Skipped unless BUILD_REAL=1 (needs root + libguestfs + the stock image
# + network + a ~30-min Suricata compile). This is the genuine proof the Suricata build is
# correct: it asserts the baked image's Suricata reports the NFQ + JA3 IPS features.

@test "real bake produces an image whose Suricata has NFQ + JA3 (BUILD_REAL only)" {
  [ "${BUILD_REAL:-}" = "1" ] || skip "set BUILD_REAL=1 (root + libguestfs) to run the real bake"
  command -v virt-customize >/dev/null || skip "virt-customize not installed"
  run sudo BUILD_REAL=1 "$BUILD_ROOT/build-guard-image.sh"
  [ "$status" -eq 0 ]
  source "$BUILD_ROOT/lib/build-common.sh"
  [ -f "$(bc_out_image)" ]
  [ -f "$(bc_manifest_path)" ]
  run sudo virt-customize -a "$(bc_out_image)" --run-command "suricata --build-info"
  [[ "$output" == *"NFQ"* ]]
  [[ "$output" == *"JA3"* ]]
}
