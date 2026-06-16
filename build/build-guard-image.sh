#!/usr/bin/env bash
# Bake the Kicksecure guard image. Dry-run via BUILD_DRY_RUN=1; a REAL bake
# (root + libguestfs + ~30min Suricata compile) requires BUILD_REAL=1.
set -euo pipefail
SELF_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=lib/build-common.sh
source "$SELF_DIR/lib/build-common.sh"

usage() { echo "Usage: build-guard-image.sh [--check]   (set BUILD_REAL=1 for a real bake)"; }

preflight() {
  local missing=0 t
  while read -r t; do command -v "$t" >/dev/null || { bc_log "missing: $t"; missing=1; }; done < <(bc_preflight_tools)
  return "$missing"
}

main() {
  case "${1:-}" in --check) preflight; exit $?;; -h|--help) usage; exit 0;; esac
  if [[ "$BUILD_DRY_RUN" != "1" && "$BUILD_REAL" != "1" ]]; then
    bc_log "refusing to run a real bake without BUILD_REAL=1 (or set BUILD_DRY_RUN=1 to preview)"; exit 2
  fi
  preflight || { [[ "$BUILD_DRY_RUN" == "1" ]] || exit 1; }

  bc_acquire_stock
  bc_log "creating working image from stock"
  bc_run qemu-img convert -O qcow2 "$(bc_stock_image)" "$(bc_out_image)"
  bc_customize "$(bc_out_image)"
  bc_dmverity_setup "$(bc_out_image)"
  if [[ "$BUILD_DRY_RUN" == "1" ]]; then bc_log "manifest (dry-run skipped hashing)"; else bc_write_manifest; fi
  bc_log "done: $(bc_out_image)"
}
main "$@"
