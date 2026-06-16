# Guard image build pipeline

Bakes a stock Kicksecure qcow2 into `kicksecure-guard-<ver>.qcow2` with Suricata 8.0.4
(source), OpenSnitch, Cowrie, host hardening, and a provenance manifest.

## Preview (no changes made)
    BUILD_DRY_RUN=1 ./build/build-guard-image.sh

## Real bake (root; libguestfs; ~30 min Suricata compile; network)
    sudo BUILD_REAL=1 ./build/build-guard-image.sh
    # opt out of dm-verity:  sudo BUILD_REAL=1 BUILD_DMVERITY=0 ./build/build-guard-image.sh

Output + `*.manifest.json` land in `$BC_STAGE` (default /var/lib/kguard-images).
The optional detectors (Zeek/dnscrypt/CrowdSec/Falco/debsums) are installed but disabled;
Plan C wires the inline Suricata IPS data path and flips toggles via `/etc/kguard.conf`.

## Status

Plan B delivers the pipeline structure and its logic is verified by the dry-run unit
suite (mocked `virt-customize`/`curl`/`gpg`). The full `BUILD_REAL=1` bake is opt-in and
not yet exercised — `build/tests/real_build.bats` is the proof step and is skipped until
run. The following are known prerequisites/gaps to resolve before (or during) the first real bake:

- ~~**External apt repos:**~~ Resolved — `opensnitch` (1.6.9) and `falco` (0.44) are both in
  Debian 13 (trixie, Kicksecure's base), so `apt-get install` works directly; no signing-key/source
  wiring needed. The live bake already brought `opensnitch.service` up active.
- ~~**Cowrie packaging:**~~ Resolved (Gap #4) — cowrie 3.0 bundles its data tree; the provisioner
  pins `cowrie==3.0.0`, ships a runnable `/opt/cowrie/etc/cowrie.cfg`, and the unit uses cowrie 3.0's
  `COWRIE_STDOUT=yes` foreground mode (the old `cowrie start -n` was an invalid flag). Live-validated:
  binds ssh 2222 + telnet 2223.
- ~~**Checksum filename:**~~ Resolved — `bc_acquire_stock` now compares digest values via
  `bc_expected_hash` (filename-agnostic), since Kicksecure's `.sha256` names the upstream file, not
  our renamed `kicksecure-stock.qcow2`.
- ~~**Preflight:**~~ Resolved — `--check` now requires `veritysetup` (cryptsetup-bin) via
  `bc_preflight_tools` whenever dm-verity is enabled (`BUILD_DMVERITY!=0`).
- **dm-verity:** still a plan-preview only (`bc_dmverity_setup` does not produce a real hashtree);
  real verified-root wiring (raw conversion + hash capture + initramfs) is deferred — the one
  remaining real-bake gap.

## Inline IPS data path (Plan C)

Nested Whonix egress is forced through L1's kernel so Suricata can drop it:

```
[L2] WS -> Whonix GW -(Tor)-> TAP kg-gw0 on br-whonix
[L1]  nft forward: established accept; new -> queue 0 (Suricata, fail-closed); else DROP
      nat: masquerade -> uplink ; IPv6 dropped
```

- **Fail-closed:** Suricata runs `-q 0` with NO `--queue-bypass`; if it dies, the nft forward
  policy `drop` means the nested stack loses connectivity rather than leaking.
- **Units:** `kguard-net` (bridge/TAP + nft), `suricata-ips` (NFQUEUE), `whonix-autostart`
  (boots nested Whonix after both).
- **Feature toggles:** optional detectors (Zeek/dnscrypt/CrowdSec/Falco) are off unless enabled
  in `/etc/kguard.conf`; `kguard-features.sh` applies the plan at boot.
- **Nested launcher:** the TAP-patched whonix-runner is vendored at `build/guest/whonix-runner/`
  (+ `PLAN-C-TAP.patch`) and copied into the image by the provisioner. The leak-test
  (`build/tests/integration_ips.bats`, `KGUARD_INTEGRATION=1`) is the end-to-end proof, run on a
  real `BUILD_REAL=1` bake.

## Tests
    bats build/tests/*.bats
