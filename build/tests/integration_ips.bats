load helper

# Opt-in end-to-end PROOF of the appliance. Skipped unless KGUARD_INTEGRATION=1 — it needs a
# real Plan-B-baked guard image + a nested-KVM-capable host. This is the final acceptance step,
# run by the operator after a `BUILD_REAL=1` bake. Its assertions can only be written and
# validated against a live image, so the body is an explicit, labeled scaffold.

@test "nested Whonix boots and a non-Tor packet from the WS is dropped (KGUARD_INTEGRATION only)" {
  [ "${KGUARD_INTEGRATION:-}" = "1" ] || skip "set KGUARD_INTEGRATION=1 (needs a baked guard image + nested KVM)"
  command -v qemu-system-x86_64 >/dev/null || skip "qemu-system-x86_64 not installed"

  # Run kguard WITHOUT the test mocks on PATH (we want the real launcher + real qemu here).
  real_path="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v "tests/mock" | paste -sd: -)"

  # 1. boot the guard (L1)
  PATH="$real_path" "$PROJECT_ROOT/bin/kguard" start

  # 2. wait for L1 + nested Whonix to come up (poll kguard health via guest-exec).
  #    TODO(real): loop on `kguard health` until "nested VMs" shows gateway+workstation running.

  # 3. assert the IPS is active + fail-closed:
  #    via guest-exec: `systemctl is-active suricata-ips` == active
  #    via guest-exec: `nft list chain inet kguard forward` shows `policy drop` and `queue num 0`

  # 4. LEAK TEST (the point): from the nested Workstation, attempt a non-Tor packet to a sink
  #    (e.g. a raw UDP/TCP to a host-side listener that is NOT a Tor guard). Assert it is DROPPED:
  #    the Suricata drop counter increments AND the host-side listener never receives it.

  # 5. assert Cowrie catches a probe: knock on L1:2222, then check cowrie's json log grew.

  # 6. teardown
  PATH="$real_path" "$PROJECT_ROOT/bin/kguard" stop

  skip "scaffold: fill in the live guest-exec + leak assertions against a real baked image"
}
