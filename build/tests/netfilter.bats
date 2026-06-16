load helper

@test "nft ruleset: fail-closed leak guard with NFQUEUE + masquerade + ipv6 drop" {
  run bash -c "source \"$BUILD_ROOT/guest/lib/provision-common.sh\"; pc_nft_ruleset"
  [ "$status" -eq 0 ]
  [[ "$output" == *"table inet kguard"* ]]
  [[ "$output" == *"queue num 0"* ]]
  [[ "$output" == *"ct state established,related accept"* ]]
  [[ "$output" == *"masquerade"* ]]
  [[ "$output" == *"policy drop"* ]]
  [[ "$output" == *"meta nfproto ipv6 drop"* ]]
}

@test "nft ruleset passes 'nft -c' syntax check when nft is available" {
  command -v nft >/dev/null || skip "nft not installed"
  run bash -c "source \"$BUILD_ROOT/guest/lib/provision-common.sh\"; pc_nft_ruleset | nft -c -f -"
  [ "$status" -eq 0 ]
}
