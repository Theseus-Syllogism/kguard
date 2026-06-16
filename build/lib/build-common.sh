# shellcheck shell=bash
# Pure host-side helpers + pinned constants for the guard image build. No side effects.
: "${BC_STAGE:=/var/lib/kguard-images}"
: "${SURICATA_VERSION:=8.0.4}"
: "${GUARD_VERSION:=0.1.0}"
# Stock Kicksecure KVM image (operator pins exact URL/version at build time; override via env).
: "${KICKSECURE_IMG_URL:=https://download.kicksecure.com/libvirt/Kicksecure-Xfce.qcow2}"
: "${SURICATA_SRC_URL:=https://www.openinfosecfoundation.org/download/suricata-${SURICATA_VERSION}.tar.gz}"
: "${BUILD_DRY_RUN:=}"
: "${BUILD_REAL:=}"
: "${BUILD_DMVERITY:=1}"

bc_suricata_version() { printf '%s\n' "$SURICATA_VERSION"; }
bc_guard_version()    { printf '%s\n' "$GUARD_VERSION"; }
bc_kicksecure_url()   { printf '%s\n' "$KICKSECURE_IMG_URL"; }
bc_suricata_url()     { printf '%s\n' "$SURICATA_SRC_URL"; }
bc_stock_image()      { printf '%s\n' "$BC_STAGE/kicksecure-stock.qcow2"; }
bc_out_image()        { printf '%s\n' "$BC_STAGE/kicksecure-guard-$(bc_guard_version).qcow2"; }
bc_manifest_path()    { printf '%s\n' "$(bc_out_image).manifest.json"; }

# Host tools the real bake needs. veritysetup (cryptsetup-bin) is only required when dm-verity is
# enabled (the default); BUILD_DMVERITY=0 drops it. Printed (one per line) so it's testable.
bc_preflight_tools() {
  printf '%s\n' qemu-img virt-customize curl
  [[ "${BUILD_DMVERITY:-1}" != "0" ]] && printf '%s\n' veritysetup
  return 0
}

# Extract the SHA-256 digest from a checksum file, ignoring the filename it references. Kicksecure's
# published .sha256 names the upstream image, not our renamed kicksecure-stock.qcow2, so a plain
# `sha256sum -c` looks for the wrong file; we compare digest values instead. Nonzero if none found.
bc_expected_hash() {
  local sf="${1:?sha256 file}" h
  h="$(grep -ioE '[0-9a-f]{64}' "$sf" 2>/dev/null | head -1)"
  [[ -n "$h" ]] || return 1
  printf '%s\n' "$h"
}

bc_log() { printf '[build] %s\n' "$*" >&2; }
# In dry-run, print the command instead of executing it. Returns success either way.
bc_run() { if [[ "$BUILD_DRY_RUN" == "1" ]]; then printf 'DRYRUN %s\n' "$*"; else "$@"; fi; }

# Download + verify the stock Kicksecure image into BC_STAGE. Idempotent (skips if present).
# Verification: SHA256 + detached GPG signature (operator must have the Kicksecure signing key
# imported). curl/gpg/sha256sum are real here; mocked only in tests.
bc_acquire_stock() {
  local img; img="$(bc_stock_image)"
  [[ -e "$img" ]] && { bc_log "stock image present: $img"; return 0; }
  bc_log "downloading stock Kicksecure image"
  curl -fSL -o "$img" "$(bc_kicksecure_url)" || { rm -f "$img"; return 1; }
  curl -fSL -o "$img.sha256" "$(bc_kicksecure_url).sha256" || true
  if [[ -s "$img.sha256" ]]; then
    bc_log "verifying sha256"
    local want got
    want="$(bc_expected_hash "$img.sha256" || true)"
    got="$(sha256sum "$img" 2>/dev/null | awk '{print $1}')"
    if [[ -z "$want" || "$want" != "$got" ]]; then
      bc_log "WARNING: sha256 check did not pass (want=${want:-none} got=${got:-none})"
      [[ "$BUILD_REAL" == "1" ]] && { rm -f "$img"; return 1; }
      true   # lenient for dry-run/tests; set -e safe
    fi
  fi
  curl -fSL -o "$img.asc" "$(bc_kicksecure_url).asc" || true
  if [[ -s "$img.asc" ]]; then
    bc_log "verifying GPG signature"
    gpg --verify "$img.asc" "$img" 2>/dev/null || {
      bc_log "WARNING: gpg verify did not pass"
      [[ "$BUILD_REAL" == "1" ]] && { rm -f "$img"; return 1; }
      true
    }
  fi
}

# Drive virt-customize against the working image $1: copy the provisioner tree into the guest
# and run it. (apt-transport-tor wiring + service config happen inside provision.sh.)
bc_customize() {
  local img="${1:?image}"
  local guest_dir; guest_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../guest" && pwd)"
  bc_run virt-customize -a "$img" \
    --copy-in "$guest_dir:/opt" \
    --run-command "chmod +x /opt/guest/provision.sh" \
    --run-command "/opt/guest/provision.sh" \
    --run-command "rm -rf /opt/guest" \
    --truncate /etc/machine-id
}

# Write a provenance manifest next to the built image (versions, source URLs, image hash).
# kicksecure_image_url is the *configured* download URL (may be a default placeholder when the
# operator stages a base image by hand); base_image_sha256 pins the *actual* staged base that was
# baked, so provenance is verifiable regardless of how the base was obtained.
bc_write_manifest() {
  local img m sha base bsha
  img="$(bc_out_image)"; m="$(bc_manifest_path)"
  sha="$(sha256sum "$img" 2>/dev/null | awk '{print $1}')"
  base="$(bc_stock_image)"
  bsha="$(sha256sum "$base" 2>/dev/null | awk '{print $1}')"
  cat > "$m" <<EOF
{
  "guard_version": "$(bc_guard_version)",
  "suricata_version": "$(bc_suricata_version)",
  "suricata_src_url": "$(bc_suricata_url)",
  "kicksecure_image_url": "$(bc_kicksecure_url)",
  "base_image": "$(basename "$base")",
  "base_image_sha256": "${bsha:-unknown}",
  "image": "$(basename "$img")",
  "image_sha256": "${sha:-unknown}",
  "dmverity_root_hash": "${BC_DMVERITY_ROOT_HASH:-}"
}
EOF
  bc_log "manifest: $m"
}

# dm-verity PLAN PREVIEW — not yet a working real bake. A real verified root requires:
# qemu-img convert -O raw, veritysetup format on the RAW root, capturing 'Root hash:', plus
# initramfs + read-only-root + /var overlay wiring. That is deferred (real-bake hardening /
# Plan C). We intentionally do NOT run veritysetup against the qcow2 here — it would silently
# produce a bad hashtree, and its stdout root hash is not captured. Opt out with BUILD_DMVERITY=0.
# TODO(real-bake): raw conversion + 'Root hash:' capture into BC_DMVERITY_ROOT_HASH + initramfs.
bc_dmverity_setup() {
  local img="${1:?image}"
  if [[ "$BUILD_DMVERITY" == "0" ]]; then bc_log "dm-verity: skip (BUILD_DMVERITY=0)"; printf 'skip\n'; return 0; fi
  bc_log "dm-verity: PLAN ONLY (real hashtree wiring deferred) for $img"
  printf 'PLAN veritysetup format <raw-root-of %s> (deferred)\n' "$img"
  export BC_DMVERITY_ROOT_HASH="${BC_DMVERITY_ROOT_HASH:-pending-real-build}"
}
