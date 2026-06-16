#!/usr/bin/env bash
# Runs INSIDE the image (copied in + executed by virt-customize). Installs the guard's
# security stack and applies base hardening. PROVISION_DRY_RUN=1 prints the plan instead
# of executing (used by tests on the host).
set -euo pipefail
SELF_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=lib/provision-common.sh
source "$SELF_DIR/lib/provision-common.sh"
: "${SURICATA_VERSION:=8.0.4}"
: "${COWRIE_VERSION:=3.0.0}"

# shellcheck disable=SC2294,SC2086
run() { if [[ "${PROVISION_DRY_RUN:-}" == "1" ]]; then printf 'DRY %s\n' "$*"; else eval "$*"; fi; }

main() {
  # 0. De-torify apt for the bake. Kicksecure ships apt-transport-tor and routes apt via
  #    tor+https://127.0.0.1:9050, but no Tor daemon runs inside the virt-customize appliance,
  #    so apt cannot connect. Strip the tor+ transport (direct HTTPS over the host egress) for
  #    the bake; restored at the end so the runtime keeps Kicksecure's Tor-apt default.
  run "sed -i.kguardbak -E 's#tor\\+https?://#https://#g' /etc/apt/sources.list 2>/dev/null || true"
  run "for f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do [ -e \"\$f\" ] && sed -i.kguardbak -E 's#tor\\+https?://#https://#g' \"\$f\"; done || true"

  # 0b. Block package postinsts from starting daemons during the bake. A daemon started by a
  #     postinst (e.g. opensnitchd) holds /dev and makes libguestfs's teardown umount fail
  #     ('target is busy'), which also truncates the flush of late writes. Restored in step 8.
  run "printf '#!/bin/sh\\nexit 101\\n' > /usr/sbin/policy-rc.d && chmod 0755 /usr/sbin/policy-rc.d"

  # 1. packages — installed individually so one unavailable package (e.g. an optional detector
  #    not present in this Debian suite) does not abort the bake; missing ones log a NOTE.
  run "apt-get update"
  { pc_required_packages; pc_optional_packages; } | tr '\n' ' ' | tr ' ' '\n' | while read -r _pkg; do
    [ -n "$_pkg" ] && run "dpkg -s $_pkg >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get install -y $_pkg || echo \"NOTE: package unavailable, skipped: $_pkg\""
  done
  # The Suricata build toolchain MUST be present (hard fail with a clear message otherwise).
  run "command -v gcc >/dev/null && command -v make >/dev/null && command -v cargo >/dev/null || { echo 'FATAL: build toolchain (gcc/make/cargo) missing'; exit 1; }"

  # 2. Suricata from source
  run "curl -fSL -o /tmp/suricata.tar.gz https://www.openinfosecfoundation.org/download/suricata-${SURICATA_VERSION}.tar.gz"
  run "tar -C /tmp -xzf /tmp/suricata.tar.gz"
  run "cd /tmp/suricata-${SURICATA_VERSION} && ./configure $(pc_suricata_configure_args | tr '\n' ' ')"
  run "cd /tmp/suricata-${SURICATA_VERSION} && make -j\$(nproc) && make install-full"
  run "ldconfig"
  run "suricata -V"

  # 3. Cowrie (dedicated user + venv). cowrie 3.0 bundles its data tree, so a pinned pip install +
  #    a runnable etc/cowrie.cfg + writable var/ dirs is a complete, startable honeypot (the unit
  #    uses cowrie 3.0's COWRIE_STDOUT=yes foreground mode — see pc_cowrie_unit).
  run "useradd -r -m -d /opt/cowrie cowrie || true"
  # su (not sudo): sudo may be absent in the virt-customize bake chroot.
  run "su -s /bin/bash -c 'python3 -m venv /opt/cowrie/venv' cowrie"
  run "su -s /bin/bash -c '/opt/cowrie/venv/bin/pip install --no-input cowrie==${COWRIE_VERSION}' cowrie || echo 'NOTE: cowrie pip install failed (network/version) — install before enabling cowrie'"
  # cowrie's writable state/log dirs (cowrie.cfg uses absolute paths under these; the unit's
  # ProtectSystem=strict permits writes only to /opt/cowrie/var).
  run "install -d -o cowrie -g cowrie /opt/cowrie/etc /opt/cowrie/var/log/cowrie /opt/cowrie/var/lib/cowrie/tty /opt/cowrie/var/lib/cowrie/downloads /opt/cowrie/var/run"
  if [[ "${PROVISION_DRY_RUN:-}" == "1" ]]; then
    printf 'DRY write /opt/cowrie/etc/cowrie.cfg\n'
    printf 'DRY write /etc/systemd/system/cowrie.service\n'
  else
    pc_cowrie_cfg > /opt/cowrie/etc/cowrie.cfg; chown cowrie:cowrie /opt/cowrie/etc/cowrie.cfg
    pc_cowrie_unit > /etc/systemd/system/cowrie.service
  fi

  # 4. hardening: sysctl + AppArmor profile for qemu
  run "install -m 0644 $SELF_DIR/files/99-kguard-hardening.conf /etc/sysctl.d/99-kguard-hardening.conf"
  run "install -m 0644 $SELF_DIR/files/usr.bin.qemu-system-x86_64 /etc/apparmor.d/usr.bin.qemu-system-x86_64"

  # 5. systemd hardening drop-ins for the long-running daemons (suricata's device-permitting
  #    inline unit is written in Plan C, so it is not hardened generically here)
  local unit
  for unit in opensnitch cowrie; do
    run "mkdir -p /etc/systemd/system/${unit}.service.d"
    if [[ "${PROVISION_DRY_RUN:-}" == "1" ]]; then
      printf 'DRY write /etc/systemd/system/%s.service.d/10-hardening.conf\n' "$unit"
    else
      pc_systemd_hardening_dropin "$unit" > "/etc/systemd/system/${unit}.service.d/10-hardening.conf"
    fi
  done

  # 6. service enable/disable plan (best-effort: a missing/unavailable unit logs, never aborts)
  pc_service_plan | while read -r verb svc; do run "systemctl $verb $svc || echo \"NOTE: systemctl $verb $svc failed (unit missing/unavailable)\""; done

  # 7. inline-IPS wiring: nft leak-guard ruleset, network/IPS/autostart units, helper scripts
  run "mkdir -p /etc/nftables.d /etc/systemd/system /usr/local/sbin /etc/suricata /var/lib/suricata/rules /var/lib/whonix-images /var/lib/whonix-runner"
  # empty ruleset so the inline suricata.yaml's rule-files reference resolves on first boot
  # (runtime suricata-update populates it later); don't clobber rules if already present.
  run "[ -e /var/lib/suricata/rules/suricata.rules ] || : > /var/lib/suricata/rules/suricata.rules"
  if [[ "${PROVISION_DRY_RUN:-}" == "1" ]]; then
    printf 'DRY write /etc/nftables.d/kguard.conf\n'
    printf 'DRY write /etc/suricata/suricata.yaml\n'
    printf 'DRY write /etc/systemd/system/suricata-ips.service\n'
    printf 'DRY write /etc/systemd/system/kguard-net.service\n'
    printf 'DRY write /etc/systemd/system/whonix-autostart.service\n'
    printf 'DRY write /etc/systemd/system/kguard-whonix-prep.service\n'
    printf 'DRY write /usr/local/sbin/kguard-net-setup.sh\n'
    printf 'DRY write /usr/local/sbin/kguard-whonix-prep.sh\n'
    printf 'DRY append /etc/fstab (9p: whonix-images, kguard-config)\n'
    printf 'DRY install /usr/local/sbin/kguard-features.sh\n'
  else
    pc_nft_ruleset             > /etc/nftables.d/kguard.conf
    pc_suricata_yaml           > /etc/suricata/suricata.yaml
    pc_suricata_ips_unit       > /etc/systemd/system/suricata-ips.service
    pc_kguard_net_unit         > /etc/systemd/system/kguard-net.service
    pc_whonix_autostart_unit   > /etc/systemd/system/whonix-autostart.service
    pc_whonix_prep_unit        > /etc/systemd/system/kguard-whonix-prep.service
    pc_kguard_net_setup_script > /usr/local/sbin/kguard-net-setup.sh
    pc_whonix_prep_script      > /usr/local/sbin/kguard-whonix-prep.sh
    chmod +x /usr/local/sbin/kguard-net-setup.sh /usr/local/sbin/kguard-whonix-prep.sh
    pc_fstab_entries          >> /etc/fstab
    install -m 0755 "$SELF_DIR/files/kguard-features.sh" /usr/local/sbin/kguard-features.sh
  fi
  # vendor the nested launcher (whonix-runner) with the TAP uplink (see PLAN-C-TAP.patch).
  # The upstream whonix-runner source must be placed at build/guest/whonix-runner/ before a
  # real bake; if absent we log a clear NOTE rather than failing the (dry-run) pipeline.
  run "if [ -d /opt/guest/whonix-runner/bin ]; then cp -a /opt/guest/whonix-runner /opt/whonix-runner && /opt/whonix-runner/install.sh; else echo 'NOTE: whonix-runner not vendored — add build/guest/whonix-runner/ (real source + PLAN-C-TAP.patch) before a real bake'; fi"
  run "systemctl enable kguard-net.service suricata-ips.service kguard-whonix-prep.service whonix-autostart.service"

  # 8. remove the bake-time service-start block + restore Kicksecure's Tor-apt transport
  run "rm -f /usr/sbin/policy-rc.d"
  run "for f in /etc/apt/sources.list.kguardbak /etc/apt/sources.list.d/*.kguardbak; do [ -e \"\$f\" ] && mv -f \"\$f\" \"\${f%.kguardbak}\"; done || true"
}
main "$@"
