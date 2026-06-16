load helper
run_sp() { KGUARD_SETPASS_STDIN=1 printf '%s\n%s\n' "$1" "$2" | "$PROJECT_ROOT/bin/kguard-setpass"; }

@test "setpass writes a 0600 keyfile with no trailing newline" {
  source "$PROJECT_ROOT/lib/kguard-common.sh"
  run bash -c "printf 'hunter2\nhunter2\n' | KGUARD_SETPASS_STDIN=1 BATS_TEST_TMPDIR='$BATS_TEST_TMPDIR' KGUARD_HOME='$KGUARD_HOME' '$PROJECT_ROOT/bin/kguard-setpass'"
  [ "$status" -eq 0 ]
  [ "$(stat -c '%a' "$(kg_keyfile)")" = "600" ]
  [ "$(cat "$(kg_keyfile)")" = "hunter2" ]
  [ "$(wc -c < "$(kg_keyfile)")" -eq 7 ]
}

@test "setpass aborts when entries differ" {
  run bash -c "printf 'a\nb\n' | KGUARD_SETPASS_STDIN=1 BATS_TEST_TMPDIR='$BATS_TEST_TMPDIR' KGUARD_HOME='$KGUARD_HOME' '$PROJECT_ROOT/bin/kguard-setpass'"
  [ "$status" -ne 0 ]; [[ "$output" == *"do not match"* ]]
}

@test "setpass refuses an empty passphrase" {
  run bash -c "printf '\n\n' | KGUARD_SETPASS_STDIN=1 BATS_TEST_TMPDIR='$BATS_TEST_TMPDIR' KGUARD_HOME='$KGUARD_HOME' '$PROJECT_ROOT/bin/kguard-setpass'"
  [ "$status" -ne 0 ]; [[ "$output" == *"must not be empty"* ]]
}

@test "setpass refuses to change password while an overlay exists" {
  : > "$BATS_TEST_TMPDIR/home/guard-overlay.qcow2"
  run bash -c "printf 'x\nx\n' | KGUARD_SETPASS_STDIN=1 BATS_TEST_TMPDIR='$BATS_TEST_TMPDIR' KGUARD_HOME='$KGUARD_HOME' '$PROJECT_ROOT/bin/kguard-setpass'"
  [ "$status" -ne 0 ]; [[ "$output" == *"reset"* ]]
}
