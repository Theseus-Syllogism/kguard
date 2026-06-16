load helper
SRC="source \"$BUILD_ROOT/guest/lib/provision-common.sh\""

@test "gateway external netdev is a TAP on the L1 bridge (not SLIRP user)" {
  run bash -c "$SRC; pc_whonix_tap_netdev"
  [[ "$output" == *"tap"* ]]
  [[ "$output" == *"ifname=kg-gw0"* ]]
  [[ "$output" == *"script=no"* ]]
  [[ "$output" != *"user,"* ]]
}
