load helper
run_cli() { "$PROJECT_ROOT/bin/kguard" "$@"; }

@test "no args prints usage and exits non-zero" {
  run run_cli; [ "$status" -ne 0 ]; [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"start"* ]] && [[ "$output" == *"stop"* ]]
}

@test "unknown subcommand errors" {
  run run_cli frobnicate; [ "$status" -ne 0 ]; [[ "$output" == *"unknown"* ]]
}

@test "start fails closed without a keyfile (no VM launched)" {
  run run_cli start
  [ "$status" -ne 0 ]; [[ "$output" == *"kguard-setpass"* ]]
  ! grep -q qemu-system "$MOCK_LOG"
}

@test "start creates overlay + state disk and launches the guard VM" {
  printf 'pw' > "$KGUARD_HOME/.luks.key"; chmod 600 "$KGUARD_HOME/.luks.key"
  run run_cli start
  [ "$status" -eq 0 ]
  grep -q 'qemu-img create' "$MOCK_LOG"
  grep -q 'whonix-state.qcow2' "$MOCK_LOG"
  grep -q 'kicksecure-guard' "$MOCK_LOG"
}

@test "start delivers the guard key into the kguard-config share for the nested guest (0600)" {
  printf 'pw' > "$KGUARD_HOME/.luks.key"; chmod 600 "$KGUARD_HOME/.luks.key"
  run run_cli start
  [ "$status" -eq 0 ]
  kf="$KGUARD_HOME/config/whonix.luks.key"
  [ -f "$kf" ]
  [ "$(cat "$kf")" = "pw" ]
  [ "$(stat -c '%a' "$kf")" = "600" ]
}

@test "status reports the guard role" {
  printf 'pw' > "$KGUARD_HOME/.luks.key"; chmod 600 "$KGUARD_HOME/.luks.key"
  run run_cli status
  [ "$status" -eq 0 ]; [[ "$output" == *"guard"* ]]
}

@test "view rejects an unknown role" {
  run run_cli view bogus; [ "$status" -ne 0 ]
}

@test "stop is cleanup-safe when not running and removes stale sockets" {
  : > "$KGUARD_HOME/guard.qmp"; : > "$KGUARD_HOME/guard-vnc.sock"
  run run_cli stop
  [ "$status" -eq 0 ]; [[ "$output" == *"Stopped."* ]]
  [ ! -e "$KGUARD_HOME/guard.qmp" ]
  [ ! -e "$KGUARD_HOME/guard-vnc.sock" ]
}

@test "health degrades gracefully when the guard is not running" {
  run run_cli health
  [ "$status" -eq 0 ]
  [[ "$output" == *"not running"* || "$output" == *"health"* ]]
}

@test "view ws explains the nested two-hop forward recipe" {
  DISPLAY= run run_cli view ws
  [ "$status" -eq 0 ]
  [[ "$output" == *"ws-vnc.sock"* ]]
  [[ "$output" == *"5902"* ]]
}
