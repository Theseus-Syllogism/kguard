load helper
# $BUILD_ROOT is set by setup() before each test; reference it inside tests (not at
# top level) so this doesn't depend on bats' file-source ordering.

@test "required packages include the core security tools + guest agent" {
  run bash -c "source "$BUILD_ROOT/guest/lib/provision-common.sh"; pc_required_packages"
  for pkg in opensnitch auditd aide firejail qemu-guest-agent apt-transport-tor; do
    [[ "$output" == *"$pkg"* ]]
  done
}

@test "optional packages are listed (installed-but-disabled set)" {
  run bash -c "source "$BUILD_ROOT/guest/lib/provision-common.sh"; pc_optional_packages"
  for pkg in zeek dnscrypt-proxy crowdsec falco debsums; do [[ "$output" == *"$pkg"* ]]; done
}

@test "suricata configure line carries the IPS-critical flags" {
  run bash -c "source "$BUILD_ROOT/guest/lib/provision-common.sh"; pc_suricata_configure_args"
  for flag in --enable-nfqueue --enable-af-packet; do
    [[ "$output" == *"$flag"* ]]
  done
}

@test "systemd hardening drop-in has the key directives" {
  run bash -c "source "$BUILD_ROOT/guest/lib/provision-common.sh"; pc_systemd_hardening_dropin suricata"
  for d in NoNewPrivileges=yes ProtectSystem=strict PrivateTmp=yes; do [[ "$output" == *"$d"* ]]; done
  [[ "$output" == *"[Service]"* ]]
}

@test "sysctl content disables IPv6" {
  run bash -c "source "$BUILD_ROOT/guest/lib/provision-common.sh"; pc_sysctl_hardening"
  [[ "$output" == *"net.ipv6.conf.all.disable_ipv6 = 1"* ]]
}

@test "service plan: opensnitch/cowrie/auditd enabled; optionals disabled" {
  run bash -c "source "$BUILD_ROOT/guest/lib/provision-common.sh"; pc_service_plan"
  [[ "$output" == *"enable opensnitch"* ]]
  [[ "$output" == *"enable cowrie"* ]]
  [[ "$output" == *"disable zeek"* ]]
  [[ "$output" == *"disable crowdsec"* ]]
}

@test "service plan enables qemu-guest-agent (QGA channel for kguard health)" {
  run bash -c "source "$BUILD_ROOT/guest/lib/provision-common.sh"; pc_service_plan"
  [[ "$output" == *"enable qemu-guest-agent"* ]]
}

@test "provision.sh dry-run emits the full plan: apt install, suricata build, services, hardening" {
  run env PROVISION_DRY_RUN=1 bash "$BUILD_ROOT/guest/provision.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"apt-get install"* ]]
  [[ "$output" == *"suricata"* ]]
  [[ "$output" == *"./configure"* ]]
  [[ "$output" == *"--enable-nfqueue"* ]]
  [[ "$output" == *"systemctl enable opensnitch"* ]]
  [[ "$output" == *"systemctl disable zeek"* ]]
  [[ "$output" == *"99-kguard-hardening.conf"* ]]
}

@test "provision.sh installs the IPS wiring: nft ruleset, units, whonix-runner" {
  run env PROVISION_DRY_RUN=1 bash "$BUILD_ROOT/guest/provision.sh"
  [[ "$output" == *"/etc/nftables.d/kguard.conf"* ]]
  [[ "$output" == *"suricata-ips.service"* ]]
  [[ "$output" == *"kguard-net.service"* ]]
  [[ "$output" == *"whonix-autostart.service"* ]]
  [[ "$output" == *"whonix-runner"* || "$output" == *"/usr/local/bin/whonix"* ]]
}
