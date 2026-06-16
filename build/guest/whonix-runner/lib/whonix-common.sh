# shellcheck shell=bash
# Pure helpers + config. Safe to source from scripts and tests. No side effects.
: "${WHONIX_HOME:=/var/lib/whonix-runner}"
: "${WHONIX_STAGE:=/var/lib/whonix-images}"
: "${WHONIX_GW_IMG:=$WHONIX_STAGE/Whonix-Gateway-LXQt-18.1.6.4.Intel_AMD64.qcow2}"
: "${WHONIX_WS_IMG:=$WHONIX_STAGE/Whonix-Workstation-LXQt-18.1.6.4.Intel_AMD64.qcow2}"
: "${WHONIX_GW_MEM:=2048}"; : "${WHONIX_GW_SMP:=1}"
: "${WHONIX_WS_MEM:=4096}"; : "${WHONIX_WS_SMP:=2}"
: "${WHONIX_STOP_TIMEOUT:=30}"
: "${WHONIX_WAIT_TRIES:=40}"          # internal-listener wait: tries x 0.25s (override in tests)

wh_keyfile() { printf '%s\n' "$WHONIX_HOME/.luks.key"; }
wh_overlay() { printf '%s\n' "$WHONIX_HOME/$1-overlay.qcow2"; }
wh_backing() { case "$1" in gw) printf '%s\n' "$WHONIX_GW_IMG";; ws) printf '%s\n' "$WHONIX_WS_IMG";; *) echo "wh_backing: unknown role: $1" >&2; return 1;; esac; }
wh_vnc_display() { case "$1" in gw) echo 1;; ws) echo 2;; *) echo "wh_vnc_display: unknown role: $1" >&2; return 1;; esac; }
wh_qmp() { printf '%s\n' "$WHONIX_HOME/$1.qmp"; }
wh_pidfile() { printf '%s\n' "$WHONIX_HOME/$1.pid"; }
wh_logfile() { printf '%s\n' "$WHONIX_HOME/$1.log"; }
wh_vnc_sock() { printf '%s\n' "$WHONIX_HOME/$1-vnc.sock"; }   # VNC over UNIX socket (perm-gated)
wh_int_sock() { printf '%s\n' "$WHONIX_HOME/int.sock"; }       # isolated GW<->WS L2 link

# 0 = keyfile present and exactly 0600; nonzero + message otherwise.
wh_check_keyfile_perms() {
  local kf; kf="$(wh_keyfile)"
  if [[ ! -e "$kf" ]]; then
    echo "keyfile missing: $kf — run whonix-setpass first" >&2; return 2
  fi
  local mode; mode="$(stat -c '%a' "$kf")"
  if [[ "$mode" != "600" ]]; then
    echo "keyfile $kf has mode $mode; must be 0600" >&2; return 3
  fi
  return 0
}

wh_secret_obj() { printf 'secret,id=sec0,file=%s,format=raw' "$(wh_keyfile)"; }

# Create a LUKS-encrypted qcow2 overlay backed by the pristine image. Idempotent.
# Built under umask 077 and moved into place atomically: a crash mid-create can only
# leave a *.tmp file, never a half-written overlay that looks valid.
wh_create_overlay() {
  local role="$1" ov tmp; ov="$(wh_overlay "$role")"
  [[ -e "$ov" ]] && return 0
  tmp="$ov.tmp.$$"
  ( umask 077
    qemu-img create -f qcow2 -F qcow2 -b "$(wh_backing "$role")" \
      --object "$(wh_secret_obj)" \
      -o "encrypt.format=luks,encrypt.key-secret=sec0" \
      "$tmp" ) || { rm -f "$tmp"; return 1; }
  chmod 600 "$tmp"
  mv -f "$tmp" "$ov"
}

# Print the qemu argv (one token per line) for role gw|ws.
wh_qemu_argv() {
  local role="$1" mem smp ov
  case "$role" in
    gw) mem="$WHONIX_GW_MEM"; smp="$WHONIX_GW_SMP";;
    ws) mem="$WHONIX_WS_MEM"; smp="$WHONIX_WS_SMP";;
    *)  echo "unknown role: $role" >&2; return 1;;
  esac
  ov="$(wh_overlay "$role")"
  local -a a=(
    qemu-system-x86_64
    -enable-kvm -machine q35 -cpu host
    -m "$mem" -smp "$smp"
    -name "whonix-$([ "$role" = gw ] && echo gateway || echo workstation)"
    --object "$(wh_secret_obj)"
    -blockdev "driver=file,filename=$ov,node-name=ovfile"
    -blockdev "driver=qcow2,file=ovfile,node-name=ovdisk,encrypt.format=luks,encrypt.key-secret=sec0"
    -device "virtio-blk-pci,drive=ovdisk"
    -object "rng-random,filename=/dev/urandom,id=rng0"
    -device "virtio-rng-pci,rng=rng0"
    # Explicit std VGA with 64MB vram. The q35 default VGA only has 16MB, which is
    # enough for one 1920x1080 framebuffer (~8MB) but NOT for LXQt's compositor to
    # double-buffer at that size => the Workstation desktop rendered a black root
    # window. The Gateway (1280x800, ~4MB/buffer) fit under 16MB and was unaffected.
    -vga none
    -device "VGA,vgamem_mb=64"
  )
  # NICs carry stable MACs. Whonix binds eth0/eth1 by PCI enumeration ORDER (verified:
  # upstream XML pins no MAC), so the external NIC is added first => eth0 (Tor uplink) and
  # the internal NIC second => eth1 (10.152.152.x). The internal link is a point-to-point
  # L2 segment over a filesystem-permission-gated UNIX socket (no loopback TCP to join).
  if [[ "$role" == "gw" ]]; then
    # PLAN-C-TAP: Gateway external NIC is a TAP on the L1 bridge (kg-gw0 on br-whonix, created
    # by kguard-net.service) instead of SLIRP, so egress traverses L1's kernel where Suricata
    # NFQUEUE sits. (Was: -netdev user,id=ext,net=10.0.2.0/24)
    a+=( -netdev "tap,id=ext,ifname=kg-gw0,script=no,downscript=no"
         -device "virtio-net-pci,netdev=ext,mac=52:54:00:a1:b2:01"
         -netdev "stream,id=int,server=on,addr.type=unix,addr.path=$(wh_int_sock)"
         -device "virtio-net-pci,netdev=int,mac=52:54:00:a1:b2:02" )
  else
    a+=( -netdev "stream,id=int,server=off,addr.type=unix,addr.path=$(wh_int_sock)"
         -device "virtio-net-pci,netdev=int,mac=52:54:00:a1:b2:03" )
  fi
  # VNC + QMP over UNIX sockets: no loopback TCP port for a local user to connect to;
  # access is gated by the 0700 WHONIX_HOME directory. Remote viewing uses 'ssh -L'.
  a+=( -vnc "unix:$(wh_vnc_sock "$role")"
       -qmp "unix:$(wh_qmp "$role"),server,nowait"
       -pidfile "$(wh_pidfile "$role")" )
  # Guest serial console is discarded by default (a cleartext host-disk log would defeat
  # the at-rest overlay encryption). Opt in with WHONIX_SERIAL_LOG=1 for debugging.
  if [[ "${WHONIX_SERIAL_LOG:-}" == "1" ]]; then
    a+=( -serial "file:$(wh_logfile "$role")" )
  else
    a+=( -serial none )
  fi
  a+=( -display none -daemonize )
  printf '%s\n' "${a[@]}"
}

# Wait (briefly) for the gateway's internal-link socket to appear before the workstation
# connects. Best-effort: returns 0 on timeout so a missing 'ss' never blocks boot.
wh_wait_internal_listener() {
  local sock tries=0; sock="$(wh_int_sock)"
  while (( tries < WHONIX_WAIT_TRIES )); do
    [[ -e "$sock" ]] && return 0
    sleep 0.25; tries=$((tries+1))
  done
  return 0
}

# Send QMP system_powerdown to a role's monitor socket.
wh_qmp_powerdown() {
  local sock; sock="$(wh_qmp "$1")"; [[ -S "$sock" ]] || return 0
  command -v socat >/dev/null || return 0
  printf '%s\n' '{"execute":"qmp_capabilities"}' '{"execute":"system_powerdown"}' \
    | socat - "UNIX-CONNECT:$sock" >/dev/null 2>&1 || true
}
