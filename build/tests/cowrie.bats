load helper
SRC="source \"$BUILD_ROOT/guest/lib/provision-common.sh\""

# Gap #4 (RUNTIME-FINDINGS-2026-06-06): cowrie stayed 'activating' — a bare pip install plus the
# old `cowrie start -n` (an invalid flag in cowrie 3.0) never produced a runnable instance.
# Provision a runnable etc/cowrie.cfg + a unit using cowrie 3.0's real foreground contract
# (COWRIE_STDOUT=yes, no -n). Verified against a live cowrie 3.0.0 run: binds 2222 (ssh) and
# 2223 (telnet) and stays up.

@test "cowrie.cfg enables the ssh+telnet honeypot (2222/2223) with json output" {
  run bash -c "$SRC; pc_cowrie_cfg"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ssh]"*"tcp:2222"* ]]
  [[ "$output" == *"[telnet]"*"tcp:2223"* ]]
  [[ "$output" == *"[output_jsonlog]"* ]]
}

@test "cowrie.cfg writes state/logs under the cowrie home (absolute, for ProtectSystem=strict)" {
  run bash -c "$SRC; pc_cowrie_cfg /opt/cowrie"
  [[ "$output" == *"/opt/cowrie/var/log/cowrie"* ]]
  [[ "$output" == *"/opt/cowrie/var/lib/cowrie"* ]]
}

@test "cowrie.cfg is valid INI (configparser parses it)" {
  run bash -c "$SRC; pc_cowrie_cfg | python3 -c 'import sys,configparser; configparser.ConfigParser().read_string(sys.stdin.read())'"
  [ "$status" -eq 0 ]
}

@test "cowrie unit uses cowrie 3.0's foreground contract (COWRIE_STDOUT=yes, not -n)" {
  run bash -c "$SRC; pc_cowrie_unit"
  [[ "$output" == *"ExecStart="*"cowrie start"* ]]
  [[ "$output" != *"cowrie start -n"* ]]
  [[ "$output" == *"COWRIE_STDOUT=yes"* ]]
  [[ "$output" == *"User=cowrie"* ]]
  [[ "$output" == *"WorkingDirectory=/opt/cowrie"* ]]
  [[ "$output" == *"ReadWritePaths=/opt/cowrie/var"* ]]
}

@test "provision.sh dry-run writes cowrie.cfg + the cowrie state dirs" {
  run env PROVISION_DRY_RUN=1 bash "$BUILD_ROOT/guest/provision.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/opt/cowrie/etc/cowrie.cfg"* ]]
  [[ "$output" == *"/opt/cowrie/var/log/cowrie"* ]]
}
