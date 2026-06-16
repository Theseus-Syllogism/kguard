load helper
SRC="source \"$BUILD_ROOT/guest/lib/provision-common.sh\""

# Gap #2 (RUNTIME-FINDINGS-2026-06-06): the default suricata.yaml is not configured for inline
# NFQUEUE, so suricata-ips never reaches stable 'active'. provision.sh must ship a known-good
# fail-closed inline config. These tests drive pc_suricata_yaml + its provisioner write.

@test "suricata.yaml configures inline NFQUEUE fail-closed (fail-open: no)" {
  run bash -c "$SRC; pc_suricata_yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"%YAML 1.1"* ]]
  [[ "$output" == *"nfq:"* ]]
  [[ "$output" == *"fail-open: no"* ]]
}

@test "suricata.yaml logs/rules paths match the suricata-ips unit ReadWritePaths" {
  run bash -c "$SRC; pc_suricata_yaml"
  [[ "$output" == *"default-log-dir: /var/log/suricata"* ]]
  [[ "$output" == *"default-rule-path: /var/lib/suricata/rules"* ]]
}

@test "suricata.yaml is well-formed YAML" {
  python3 -c 'import yaml' 2>/dev/null || skip "pyyaml not installed"
  run bash -c "$SRC; pc_suricata_yaml | python3 -c 'import sys,yaml; yaml.safe_load(sys.stdin)'"
  [ "$status" -eq 0 ]
}

@test "suricata.yaml passes 'suricata -T' with a real ruleset loaded (rule-vars resolve)" {
  command -v suricata >/dev/null || skip "suricata not installed"
  rp="$BATS_TEST_TMPDIR/rules"; mkdir -p "$rp"
  # a representative ET-style rule references the standard rule-vars; the config must define them
  # all or 'suricata -T' fails to parse signatures (an empty ruleset would mask this — see Gap #2).
  printf '%s\n' \
    'alert http $EXTERNAL_NET any -> $HTTP_SERVERS $HTTP_PORTS (msg:"kg test"; flow:established,to_server; sid:1000001; rev:1;)' \
    'alert tcp $HOME_NET any -> $EXTERNAL_NET $SSH_PORTS (msg:"kg ssh"; flow:to_server; sid:1000002; rev:1;)' \
    > "$rp/suricata.rules"
  ld="$BATS_TEST_TMPDIR/log"; mkdir -p "$ld"
  tmp="$BATS_TEST_TMPDIR/suricata.yaml"
  bash -c "$SRC; pc_suricata_yaml '$rp' '$ld'" > "$tmp"
  run suricata -T -c "$tmp"
  [ "$status" -eq 0 ]
}

@test "provision.sh dry-run writes /etc/suricata/suricata.yaml" {
  run env PROVISION_DRY_RUN=1 bash "$BUILD_ROOT/guest/provision.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/etc/suricata/suricata.yaml"* ]]
}
