# shellcheck shell=bash
# Pure helpers + config. Safe to source from scripts and tests. No side effects.
: "${KGUARD_HOME:=/var/lib/kguard}"
: "${KGUARD_STAGE:=/var/lib/whonix-images}"
: "${KGUARD_IMG:=/var/lib/kguard-images/kicksecure-guard.qcow2}"
: "${KGUARD_MEM:=10240}"; : "${KGUARD_SMP:=4}"
: "${KGUARD_STATE_SIZE:=120G}"
: "${KGUARD_STOP_TIMEOUT:=45}"
: "${KGUARD_CONFIG_SHARE:=$KGUARD_HOME/config}"   # 9p-shared into guest as kguard-config

kg_keyfile()     { printf '%s\n' "$KGUARD_HOME/.luks.key"; }
# The guard LUKS key, re-exposed inside the RO kguard-config 9p share so the guest can install
# it for the nested Whonix overlays (the guard passphrase is reused — see cmd_start).
kg_config_keyfile() { printf '%s\n' "$KGUARD_CONFIG_SHARE/whonix.luks.key"; }
kg_overlay()     { printf '%s\n' "$KGUARD_HOME/guard-overlay.qcow2"; }
kg_state_disk()  { printf '%s\n' "$KGUARD_HOME/whonix-state.qcow2"; }
kg_vnc_sock()    { printf '%s\n' "$KGUARD_HOME/guard-vnc.sock"; }
kg_qmp()         { printf '%s\n' "$KGUARD_HOME/guard.qmp"; }
kg_qga()         { printf '%s\n' "$KGUARD_HOME/guard-qga.sock"; }   # QEMU Guest Agent channel
kg_pidfile()     { printf '%s\n' "$KGUARD_HOME/guard.pid"; }
kg_logfile()     { printf '%s\n' "$KGUARD_HOME/guard.log"; }
kg_vnc_display() { echo 3; }

kg_secret_obj()  { printf 'secret,id=sec0,file=%s,format=raw' "$(kg_keyfile)"; }

# 0 = keyfile present and exactly 0600; nonzero + message otherwise.
kg_check_keyfile_perms() {
  local kf; kf="$(kg_keyfile)"
  [[ -e "$kf" ]] || { echo "keyfile missing: $kf — run kguard-setpass first" >&2; return 2; }
  local mode; mode="$(stat -c '%a' "$kf")"
  [[ "$mode" == "600" ]] || { echo "keyfile $kf has mode $mode; must be 0600" >&2; return 3; }
  return 0
}

kg_backing() { printf '%s\n' "$KGUARD_IMG"; }

# LUKS-encrypted qcow2 overlay over the (read-only) baked guard image. Idempotent + atomic.
kg_create_overlay() {
  local ov tmp; ov="$(kg_overlay)"
  [[ -e "$ov" ]] && return 0
  tmp="$ov.tmp.$$"
  ( umask 077
    qemu-img create -f qcow2 -F qcow2 -b "$(kg_backing)" \
      --object "$(kg_secret_obj)" \
      -o "encrypt.format=luks,encrypt.key-secret=sec0" \
      "$tmp" ) || { rm -f "$tmp"; return 1; }
  chmod 600 "$tmp"; mv -f "$tmp" "$ov"
}

# Plain qcow2 data disk for the nested Whonix overlays (which are themselves LUKS,
# so double-encrypting here is redundant). Idempotent.
kg_create_state_disk() {
  local d tmp; d="$(kg_state_disk)"
  [[ -e "$d" ]] && return 0
  tmp="$d.tmp.$$"
  ( umask 077; qemu-img create -f qcow2 -o "size=$KGUARD_STATE_SIZE" "$tmp" ) || { rm -f "$tmp"; return 1; }
  chmod 600 "$tmp"; mv -f "$tmp" "$d"
}

# Print the qemu argv (one token per line) for the Kicksecure guard VM.
# -cpu host passes VMX/SVM through so the nested Whonix VMs (L2) can use KVM. The host
# must have nested virt enabled (setup.sh checks this).
kg_qemu_argv() {
  local ov state; ov="$(kg_overlay)"; state="$(kg_state_disk)"
  local -a a=(
    qemu-system-x86_64
    -enable-kvm -machine q35 -cpu host
    -m "$KGUARD_MEM" -smp "$KGUARD_SMP"
    -name "kicksecure-guard"
    --object "$(kg_secret_obj)"
    -blockdev "driver=file,filename=$ov,node-name=ovfile"
    -blockdev "driver=qcow2,file=ovfile,node-name=ovdisk,encrypt.format=luks,encrypt.key-secret=sec0"
    -device "virtio-blk-pci,drive=ovdisk"
    -blockdev "driver=file,filename=$state,node-name=statefile"
    -blockdev "driver=qcow2,file=statefile,node-name=statedisk"
    -device "virtio-blk-pci,drive=statedisk"
    -object "rng-random,filename=/dev/urandom,id=rng0"
    -device "virtio-rng-pci,rng=rng0"
    -vga none -device "VGA,vgamem_mb=64"
    -fsdev "local,id=fsstage,path=$KGUARD_STAGE,security_model=none,readonly=on"
    -device "virtio-9p-pci,fsdev=fsstage,mount_tag=whonix-images"
    -fsdev "local,id=fscfg,path=$KGUARD_CONFIG_SHARE,security_model=none,readonly=on"
    -device "virtio-9p-pci,fsdev=fscfg,mount_tag=kguard-config"
    -netdev "user,id=up"
    -device "virtio-net-pci,netdev=up,mac=52:54:00:c0:ff:ee"
    -vnc "unix:$(kg_vnc_sock)"
    -qmp "unix:$(kg_qmp),server,nowait"
    # QEMU Guest Agent channel (org.qemu.guest_agent.0) — `kguard health` runs commands in L1
    # over THIS socket via guest-exec (NOT the QMP monitor, which has no guest-exec verb).
    -chardev "socket,path=$(kg_qga),server=on,wait=off,id=qga0"
    -device "virtio-serial-pci"
    -device "virtserialport,chardev=qga0,name=org.qemu.guest_agent.0"
    -pidfile "$(kg_pidfile)"
  )
  if [[ "${KGUARD_SERIAL_LOG:-}" == "1" ]]; then
    a+=( -serial "file:$(kg_logfile)" )
  else
    a+=( -serial none )
  fi
  a+=( -display none -daemonize )
  printf '%s\n' "${a[@]}"
}

# Run a shell command string inside the guard (L1) via the QEMU Guest Agent (QGA) — the guard
# image bakes qemu-guest-agent and kg_qemu_argv exposes the QGA virtio-serial socket. Echoes
# the command's stdout (base64-decoded). Best-effort: returns nonzero if socat/socket is
# unavailable. (Live path validated only against a real baked guard; unit tests exercise the
# graceful-degradation path.) NOTE: this is QGA, not the QMP monitor — there is no
# qmp_capabilities handshake, and guest-exec is a QGA verb served on the QGA channel.
kg_qga_exec() {
  local cmd="$*"
  command -v socat >/dev/null || return 1
  local sock; sock="$(kg_qga)"; [[ -S "$sock" ]] || return 1
  local reply pid out
  # shellcheck disable=SC2016
  reply="$(printf '%s\n' \
      "{\"execute\":\"guest-exec\",\"arguments\":{\"path\":\"/bin/sh\",\"arg\":[\"-c\",\"$cmd\"],\"capture-output\":true}}" \
      | socat - "UNIX-CONNECT:$sock" 2>/dev/null)" || return 1
  pid="$(printf '%s' "$reply" | sed -n 's/.*"pid":[ ]*\([0-9]\{1,\}\).*/\1/p' | head -1)"
  [[ -n "$pid" ]] || return 1
  # Poll status until the command has exited (fast commands may not be done on first read).
  for _ in 1 2 3 4 5; do
    reply="$(printf '%s\n' "{\"execute\":\"guest-exec-status\",\"arguments\":{\"pid\":$pid}}" \
        | socat - "UNIX-CONNECT:$sock" 2>/dev/null)"
    [[ "$reply" == *'"exited":true'* ]] && break
    sleep 1
  done
  out="$(printf '%s' "$reply" | sed -n 's/.*"out-data":[ ]*"\([^"]*\)".*/\1/p' | head -1)"
  [[ -n "$out" ]] && printf '%s' "$out" | base64 -d 2>/dev/null || true
}
