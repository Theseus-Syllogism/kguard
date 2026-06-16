load helper

@test "paths honor KGUARD_HOME / KGUARD_STAGE overrides" {
  source "$PROJECT_ROOT/lib/kguard-common.sh"
  [ "$(kg_keyfile)" = "$KGUARD_HOME/.luks.key" ]
  [ "$(kg_overlay)" = "$KGUARD_HOME/guard-overlay.qcow2" ]
  [ "$(kg_state_disk)" = "$KGUARD_HOME/whonix-state.qcow2" ]
  [ "$(kg_vnc_sock)" = "$KGUARD_HOME/guard-vnc.sock" ]
  [ "$(kg_qmp)" = "$KGUARD_HOME/guard.qmp" ]
}

@test "vnc display is fixed at 3" {
  source "$PROJECT_ROOT/lib/kguard-common.sh"
  [ "$(kg_vnc_display)" = "3" ]
}

@test "kg_check_keyfile_perms accepts 0600, rejects 0644, reports missing" {
  source "$PROJECT_ROOT/lib/kguard-common.sh"
  run kg_check_keyfile_perms; [ "$status" -ne 0 ]; [[ "$output" == *"kguard-setpass"* ]]
  printf 'pw' > "$(kg_keyfile)"; chmod 600 "$(kg_keyfile)"
  run kg_check_keyfile_perms; [ "$status" -eq 0 ]
  chmod 644 "$(kg_keyfile)"
  run kg_check_keyfile_perms; [ "$status" -ne 0 ]; [[ "$output" == *"0600"* ]]
}
