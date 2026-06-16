#!/usr/bin/env bash
# Boot-time: apply the optional-detector enable/disable plan from /etc/kguard.conf.
# Sourced helpers live alongside the provisioner in the image at /opt/guest/lib.
set -euo pipefail
LIB="${KGUARD_PC_LIB:-/opt/guest/lib/provision-common.sh}"
# shellcheck source=/dev/null
source "$LIB"
pc_feature_activation /etc/kguard.conf | while read -r verb svc rest; do
  case "$verb" in
    enable)    systemctl enable --now "$svc" 2>/dev/null || true ;;
    disable)   systemctl disable --now "$svc" 2>/dev/null || true ;;
    configure) : ;;  # wazuh endpoint wiring is handled separately
    skip)      : ;;
  esac
done
