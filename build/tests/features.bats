load helper
SRC="source \"$BUILD_ROOT/guest/lib/provision-common.sh\""

@test "feature activation enables only what kguard.conf turns on" {
  cfg="$BATS_TEST_TMPDIR/kguard.conf"
  printf 'ZEEK=1\nDNSCRYPT=0\nCROWDSEC=1\nFALCO=0\nDEBSUMS=0\nWAZUH_ENDPOINT=\n' > "$cfg"
  run bash -c "$SRC; pc_feature_activation '$cfg'"
  [[ "$output" == *"enable zeek"* ]]
  [[ "$output" == *"enable crowdsec"* ]]
  [[ "$output" == *"disable dnscrypt-proxy"* ]]
  [[ "$output" == *"disable falco"* ]]
}

@test "absent config => everything stays disabled (secure default)" {
  run bash -c "$SRC; pc_feature_activation /nonexistent.conf"
  [[ "$output" == *"disable zeek"* ]]
  [[ "$output" != *"enable zeek"* ]]
}
