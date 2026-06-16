load helper
SRC="source \"$BUILD_ROOT/guest/lib/provision-common.sh\""

@test "suricata-ips unit runs NFQUEUE fail-closed and binds caps" {
  run bash -c "$SRC; pc_suricata_ips_unit"
  [[ "$output" == *"[Service]"* ]]
  [[ "$output" == *"-q 0"* ]]
  [[ "$output" != *"--queue-bypass"* ]]
  [[ "$output" == *"AmbientCapabilities=CAP_NET_ADMIN"* ]]
  [[ "$output" == *"Restart=on-failure"* ]]
}

@test "kguard-net unit runs the bridge/TAP setup before the VMs" {
  run bash -c "$SRC; pc_kguard_net_unit"
  [[ "$output" == *"kguard-net-setup.sh"* ]]
  [[ "$output" == *"Type=oneshot"* ]]
  [[ "$output" == *"RemainAfterExit=yes"* ]]
}

@test "whonix-autostart ordered After net + suricata" {
  run bash -c "$SRC; pc_whonix_autostart_unit"
  [[ "$output" == *"After=kguard-net.service suricata-ips.service"* ]]
  [[ "$output" == *"Wants=kguard-net.service suricata-ips.service"* ]]
  [[ "$output" == *"whonix start"* || "$output" == *"kg-whonix"* ]]
}

@test "kguard-net-setup creates br-whonix + a gw TAP" {
  run bash -c "$SRC; pc_kguard_net_setup_script"
  [[ "$output" == *"br-whonix"* ]]
  [[ "$output" == *"tuntap"* || "$output" == *"tap"* ]]
  [[ "$output" == *"sysctl"*"ip_forward"* ]]
}
