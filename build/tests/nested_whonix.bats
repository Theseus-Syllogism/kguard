load helper
SRC="source \"$BUILD_ROOT/guest/lib/provision-common.sh\""

# Gap #1 (RUNTIME-FINDINGS-2026-06-06): whonix-autostart failed because the guest had no nested
# LUKS keyfile and the 9p shares + state disk weren't mounted. Provision fstab entries for the
# RO 9p shares, a prep oneshot (format+mount the state disk, install the nested key from the
# kguard-config share, fail-closed), and order it before whonix-autostart.

@test "fstab entries mount both 9p shares read-only (whonix-images + kguard-config)" {
  run bash -c "$SRC; pc_fstab_entries"
  [ "$status" -eq 0 ]
  [[ "$output" == *"whonix-images"*"/var/lib/whonix-images"*"9p"* ]]
  [[ "$output" == *"kguard-config"*"/run/kguard-config"*"9p"* ]]
  [[ "$output" == *"trans=virtio,version=9p2000.L,ro,nofail"* ]]
}

@test "whonix-prep unit is a oneshot ordered after the config mount, before whonix-autostart" {
  run bash -c "$SRC; pc_whonix_prep_unit"
  [[ "$output" == *"Type=oneshot"* ]]
  [[ "$output" == *"RequiresMountsFor=/run/kguard-config"* ]]
  [[ "$output" == *"Before=whonix-autostart.service"* ]]
  [[ "$output" == *"kguard-whonix-prep.sh"* ]]
}

@test "whonix-autostart now waits for prep + the nested images mount" {
  run bash -c "$SRC; pc_whonix_autostart_unit"
  [[ "$output" == *"kguard-whonix-prep.service"* ]]
  [[ "$output" == *"RequiresMountsFor="*"/var/lib/whonix-images"* ]]
}

@test "whonix-prep installs the nested key from the config share at 0600" {
  script="$BATS_TEST_TMPDIR/prep.sh"
  bash -c "$SRC; pc_whonix_prep_script" > "$script"; chmod +x "$script"
  cfg="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$cfg"; printf 'secret' > "$cfg/whonix.luks.key"
  home="$BATS_TEST_TMPDIR/wh"
  run env KGUARD_STATE_DEV="$BATS_TEST_TMPDIR/notblock" WHONIX_HOME="$home" KGUARD_CONFIG_MNT="$cfg" "$script"
  [ "$status" -eq 0 ]
  [ -f "$home/.luks.key" ]
  [ "$(cat "$home/.luks.key")" = "secret" ]
  [ "$(stat -c '%a' "$home/.luks.key")" = "600" ]
}

@test "whonix-prep fails closed when the nested key is absent" {
  script="$BATS_TEST_TMPDIR/prep.sh"
  bash -c "$SRC; pc_whonix_prep_script" > "$script"; chmod +x "$script"
  cfg="$BATS_TEST_TMPDIR/empty"; mkdir -p "$cfg"   # no whonix.luks.key delivered
  home="$BATS_TEST_TMPDIR/wh"
  run env KGUARD_STATE_DEV="$BATS_TEST_TMPDIR/notblock" WHONIX_HOME="$home" KGUARD_CONFIG_MNT="$cfg" "$script"
  [ "$status" -ne 0 ]
  [ ! -f "$home/.luks.key" ]
}

@test "whonix-prep never reformats a state disk that already has a filesystem" {
  run bash -c "$SRC; pc_whonix_prep_script"
  # the mkfs must be guarded by a blkid check so a populated nested-state disk is never wiped
  [[ "$output" == *"blkid"* ]]
  [[ "$output" == *"mkfs.ext4"* ]]
}

@test "provision.sh dry-run wires the nested-Whonix mounts + prep service" {
  run env PROVISION_DRY_RUN=1 bash "$BUILD_ROOT/guest/provision.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/etc/fstab"* ]]
  [[ "$output" == *"kguard-whonix-prep.sh"* ]]
  [[ "$output" == *"kguard-whonix-prep.service"* ]]
  [[ "$output" == *"systemctl enable"*"kguard-whonix-prep"* ]]
}
