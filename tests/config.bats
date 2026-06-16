load helper

@test "KGUARD_CONFIG supplies KGUARD_HOME when unset; env still wins" {
  cfg="$BATS_TEST_TMPDIR/kg.conf"
  printf ': "${KGUARD_HOME:=%s}"\n' "/tmp/from-config-XYZ" > "$cfg"
  run env -u KGUARD_HOME KGUARD_CONFIG="$cfg" "$PROJECT_ROOT/bin/kguard" start
  [ "$status" -ne 0 ]
  [[ "$output" == *"/tmp/from-config-XYZ/.luks.key"* ]]
  run env KGUARD_CONFIG="$cfg" "$PROJECT_ROOT/bin/kguard" start
  [[ "$output" == *"$KGUARD_HOME/.luks.key"* ]]
  [[ "$output" != *"from-config-XYZ"* ]]
}

@test "a missing config file is silently ignored" {
  run env KGUARD_CONFIG="$BATS_TEST_TMPDIR/nope.conf" "$PROJECT_ROOT/bin/kguard" status
  [ "$status" -eq 0 ]
}
