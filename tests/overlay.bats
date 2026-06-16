load helper

@test "kg_create_overlay invokes qemu-img with LUKS + secret-from-file, never the passphrase" {
  source "$PROJECT_ROOT/lib/kguard-common.sh"
  printf 'sup3rs3cret' > "$(kg_keyfile)"; chmod 600 "$(kg_keyfile)"
  kg_create_overlay
  grep -q 'qemu-img create' "$MOCK_LOG"
  grep -q 'encrypt.format=luks' "$MOCK_LOG"
  grep -q 'secret,id=sec0' "$MOCK_LOG"
  ! grep -q 'sup3rs3cret' "$MOCK_LOG"
}

@test "kg_create_overlay is a no-op when the overlay already exists" {
  source "$PROJECT_ROOT/lib/kguard-common.sh"
  : > "$(kg_overlay)"
  kg_create_overlay
  ! grep -q 'qemu-img create' "$MOCK_LOG"
}

@test "kg_create_state_disk makes a sparse qcow2 once" {
  source "$PROJECT_ROOT/lib/kguard-common.sh"
  kg_create_state_disk
  grep -q "qemu-img create -f qcow2.*whonix-state.qcow2" "$MOCK_LOG"
  : > "$MOCK_LOG"
  kg_create_state_disk
  ! grep -q 'qemu-img create' "$MOCK_LOG"
}
