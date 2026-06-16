load helper

argv() { source "$PROJECT_ROOT/lib/kguard-common.sh"; kg_qemu_argv; }

@test "argv: QEMU Guest Agent channel present (for kguard health)" {
  run argv
  echo "$output" | grep -q "org.qemu.guest_agent.0"
  echo "$output" | grep -q "id=qga0"
  echo "$output" | grep -q "guard-qga.sock"
}

@test "argv: KVM + nesting passthrough (-cpu host), resources, LUKS disk" {
  run argv
  [ "$status" -eq 0 ]
  [[ "$output" == qemu-system-x86_64* ]]
  echo "$output" | grep -qx -- '-enable-kvm'
  echo "$output" | grep -qx -- '-cpu'; echo "$output" | grep -qx -- 'host'
  echo "$output" | grep -qx -- "$KGUARD_MEM"
  echo "$output" | grep -q 'encrypt.format=luks'
  echo "$output" | grep -q 'node-name=ovdisk'
}

@test "argv: nested-state data disk attached as a second virtio-blk" {
  run argv
  echo "$output" | grep -q "whonix-state.qcow2"
  echo "$output" | grep -q 'node-name=statedisk'
}

@test "argv: Whonix images 9p-shared read-only as mount tag whonix-images" {
  run argv
  echo "$output" | grep -q "path=$KGUARD_STAGE"
  echo "$output" | grep -q 'readonly=on'
  echo "$output" | grep -q 'mount_tag=whonix-images'
}

@test "argv: kguard-config 9p share present" {
  run argv
  echo "$output" | grep -q 'mount_tag=kguard-config'
}

@test "argv: VNC+QMP over unix sockets, 64MB VGA, headless, daemonized" {
  run argv
  echo "$output" | grep -q "unix:$KGUARD_HOME/guard-vnc.sock"
  echo "$output" | grep -q "unix:$KGUARD_HOME/guard.qmp"
  echo "$output" | grep -qx -- 'VGA,vgamem_mb=64'
  echo "$output" | grep -qx -- '-display'; echo "$output" | grep -qx -- 'none'
  echo "$output" | grep -qx -- '-daemonize'
}

@test "argv never contains the passphrase" {
  printf 'leakme' > "$(kg_keyfile)"; chmod 600 "$(kg_keyfile)"
  run argv
  [[ "$output" != *"leakme"* ]]
}

@test "WHONIX-style serial is off by default; KGUARD_SERIAL_LOG=1 opts in" {
  run argv
  echo "$output" | grep -qx -- 'none'
  KGUARD_SERIAL_LOG=1 run argv
  echo "$output" | grep -q "file:$KGUARD_HOME/guard.log"
}
