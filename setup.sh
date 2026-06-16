#!/usr/bin/env bash
# kicksecure-guard interactive setup wizard. Uses gum for a TUI when present, else plain prompts.
# gum is OPTIONAL and used by this wizard only. Force the plain path with KGUARD_PLAIN=1.
# Non-interactive: KGUARD_SETUP_ASSUME_YES=1 + KGUARD_BINDIR/KGUARD_HOME/KGUARD_STAGE[/KGUARD_CONFIG].
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
: "${KGUARD_HOME:=/var/lib/kguard}"
: "${KGUARD_STAGE:=/var/lib/whonix-images}"
: "${KGUARD_BINDIR:=/usr/local/bin}"
have() { command -v "$1" >/dev/null 2>&1; }
noninteractive() { [[ "${KGUARD_SETUP_ASSUME_YES:-}" == "1" ]]; }

# Host must have nested KVM. $1 = path to the nested param (default: auto-detect intel/amd).
# shellcheck disable=SC2120
kg_wzd_check_nesting() {
  local f="${1:-}"
  if [[ -z "$f" ]]; then
    [[ -e /sys/module/kvm_intel/parameters/nested ]] && f=/sys/module/kvm_intel/parameters/nested
    [[ -e /sys/module/kvm_amd/parameters/nested ]]   && f=/sys/module/kvm_amd/parameters/nested
  fi
  [[ -n "$f" && -r "$f" ]] || { echo "nested-KVM param not found" >&2; return 1; }
  local v; v="$(cat "$f")"
  [[ "$v" == "Y" || "$v" == "1" ]] || { echo "nested KVM is disabled ($v) — enable kvm_*.nested=1" >&2; return 1; }
}

# Required: qemu-system-x86_64, qemu-img, socat. Echoes name<TAB>status; rc!=0 if any missing.
kg_wzd_check_deps() {
  local rc=0 t
  for t in qemu-system-x86_64 qemu-img socat; do
    if have "$t"; then printf '%s\tok\n' "$t"; else printf '%s\tMISSING\n' "$t"; rc=1; fi
  done
  return "$rc"
}

kg_wzd_write_config() {
  local home="$1" stage="$2" path="$3"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<EOF
# kicksecure-guard host-local config. Written by setup.sh. ':=' so env still wins.
: "\${KGUARD_HOME:=$home}"
: "\${KGUARD_STAGE:=$stage}"
EOF
}

# ---- UI primitives: use gum when present (and not forced off), else a plain-terminal fallback.
# Prompts/menus go to stderr so the value printed on stdout stays clean for `$(...)`. The plain
# fallback reads stdin (not /dev/tty), so the wizard works without gum and is unit-testable.
kg_have_gum() { [[ "${KGUARD_PLAIN:-}" != 1 ]] && have gum; }

ui_banner() {
  if kg_have_gum; then gum style --border double --padding "1 2" --foreground 212 "$1"
  else printf '\n== %s ==\n\n' "$1" >&2; fi
}
ui_ok()  { if kg_have_gum; then gum style --foreground 35 "  ✓ $1"; else printf '  [ok] %s\n' "$1" >&2; fi; }
ui_err() { if kg_have_gum; then gum style --foreground 196 "  ✗ $1"; else printf '  [!!] %s\n' "$1" >&2; fi; }

ui_confirm() {  # $1 = prompt; rc 0 = yes
  if kg_have_gum; then gum confirm "$1"
  else local a; read -rp "$1 [y/N] " a; [[ "$a" == [yY]* ]]; fi
}
ui_input() {  # $1 = label, $2 = default; prints the chosen value on stdout
  if kg_have_gum; then gum input --prompt "$1: " --value "$2"
  else local a; read -rp "$1 [$2]: " a; printf '%s\n' "${a:-$2}"; fi
}
ui_choose() {  # $1 = header, $2.. = options; prints the chosen option on stdout
  local header="$1"; shift
  if kg_have_gum; then printf '%s\n' "$@" | gum choose --header "$header"; return; fi
  local -a opts=("$@"); local i a
  printf '%s\n' "$header" >&2
  for i in "${!opts[@]}"; do printf '  %d) %s\n' "$((i+1))" "${opts[$i]}" >&2; done
  read -rp "Choose [1]: " a; a="${a:-1}"
  printf '%s\n' "${opts[$((a-1))]:-${opts[0]}}"
}
ui_run() {  # $1 = title; rest = command to run
  local title="$1"; shift
  if kg_have_gum; then gum spin --title "$title" -- "$@"; else printf '%s…\n' "$title" >&2; "$@"; fi
}

main() {
  if noninteractive; then
    KGUARD_BINDIR="$KGUARD_BINDIR" "$ROOT/install.sh"
    kg_wzd_write_config "$KGUARD_HOME" "$KGUARD_STAGE" "${KGUARD_CONFIG:-/etc/kguard.conf}"
    kg_wzd_check_deps >/dev/null || true
    echo "setup (non-interactive) done" >&2
    return 0
  fi
  ui_banner "kicksecure-guard setup"
  kg_wzd_check_nesting "${KGUARD_NESTING_FILE:-}" || ui_confirm "Nested KVM not confirmed — continue anyway?" || exit 1
  kg_wzd_check_deps | while IFS=$'\t' read -r n s; do
    [[ "$s" == ok ]] && ui_ok "$n" || ui_err "$n MISSING"
  done
  kg_wzd_check_deps >/dev/null || ui_confirm "Required deps missing — continue?" || exit 1
  local bindir home stage
  bindir="$(ui_choose "Install kguard into:" "/usr/local/bin" "$HOME/.local/bin")"
  home="$(ui_input "KGUARD_HOME" "$KGUARD_HOME")"
  stage="$(ui_input "KGUARD_STAGE" "$KGUARD_STAGE")"
  ui_confirm "Install to $bindir; HOME=$home STAGE=$stage?" || exit 1
  ui_run "Installing" env KGUARD_BINDIR="$bindir" "$ROOT/install.sh"
  kg_wzd_write_config "$home" "$stage" "${KGUARD_CONFIG:-/etc/kguard.conf}"
  ui_confirm "Set the LUKS passphrase now?" && KGUARD_HOME="$home" "$ROOT/bin/kguard-setpass" || true
  ui_banner "Setup complete — run:  kguard start"
}
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi
