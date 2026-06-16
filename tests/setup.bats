load helper

_toolbox() {
  local tb="$BATS_TEST_TMPDIR/tb"; rm -rf "$tb"; mkdir -p "$tb"; local u p
  for u in bash env readlink dirname cat mkdir id chmod ln grep; do
    p="$(command -v "$u" 2>/dev/null)" && ln -sf "$p" "$tb/$u"
  done
  for u in "$@"; do printf '#!/bin/sh\n' > "$tb/$u"; chmod +x "$tb/$u"; done
  printf '%s\n' "$tb"
}

@test "kg_wzd_check_nesting: Y means enabled, N means disabled" {
  src="source '$PROJECT_ROOT/setup.sh'"
  f="$BATS_TEST_TMPDIR/nested"; echo Y > "$f"
  run bash -c "$src; kg_wzd_check_nesting '$f'"; [ "$status" -eq 0 ]
  echo N > "$f"
  run bash -c "$src; kg_wzd_check_nesting '$f'"; [ "$status" -ne 0 ]
}

@test "kg_wzd_check_deps: all required present => rc 0; missing => non-zero" {
  tb="$(_toolbox qemu-system-x86_64 qemu-img socat)"
  run env -i PATH="$tb" bash -c "source '$PROJECT_ROOT/setup.sh'; kg_wzd_check_deps"; [ "$status" -eq 0 ]
  tb="$(_toolbox qemu-img)"
  run env -i PATH="$tb" bash -c "source '$PROJECT_ROOT/setup.sh'; kg_wzd_check_deps"; [ "$status" -ne 0 ]
  [[ "$output" == *"qemu-system-x86_64"*"MISSING"* ]]
}

@test "kg_wzd_write_config writes a sourceable ':=' config + feature flags" {
  cfg="$BATS_TEST_TMPDIR/kg.conf"
  run bash -c "source '$PROJECT_ROOT/setup.sh'; kg_wzd_write_config /a/home /a/stage '$cfg'"
  [ -f "$cfg" ]
  grep -q 'KGUARD_HOME:=/a/home' "$cfg"
  grep -q 'KGUARD_STAGE:=/a/stage' "$cfg"
}

@test "non-interactive setup installs launchers + writes config (no gum)" {
  bindir="$BATS_TEST_TMPDIR/bin"; mkdir -p "$bindir"; cfg="$BATS_TEST_TMPDIR/ni.conf"
  run env KGUARD_SETUP_ASSUME_YES=1 KGUARD_BINDIR="$bindir" \
          KGUARD_HOME=/srv/state KGUARD_STAGE=/srv/images KGUARD_CONFIG="$cfg" \
          "$PROJECT_ROOT/setup.sh"
  [ "$status" -eq 0 ]
  [ -L "$bindir/kguard" ]; [ -L "$bindir/kguard-setpass" ]
  grep -q 'KGUARD_HOME:=/srv/state' "$cfg"
}

# gum fallback: when gum is absent (KGUARD_PLAIN=1 forces it), the wizard uses plain read-prompts
# that read stdin, so they're drivable in tests. ($PROJECT_ROOT is set by setup(), so reference
# it inside the test body — not at file top level, where it isn't populated yet.)

@test "ui_input (plain) echoes the typed value, or the default on empty input" {
  src="source '$PROJECT_ROOT/setup.sh'"
  v="$(KGUARD_PLAIN=1 bash -c "$src; ui_input KGUARD_HOME /def" <<< 'typed' 2>/dev/null)"
  [ "$v" = "typed" ]
  v="$(KGUARD_PLAIN=1 bash -c "$src; ui_input KGUARD_HOME /def" <<< '' 2>/dev/null)"
  [ "$v" = "/def" ]
}

@test "ui_confirm (plain): y => rc 0, anything else => non-zero" {
  src="source '$PROJECT_ROOT/setup.sh'"
  KGUARD_PLAIN=1 bash -c "$src; ui_confirm 'ok?'" <<< 'y' 2>/dev/null && rc=0 || rc=1; [ "$rc" -eq 0 ]
  KGUARD_PLAIN=1 bash -c "$src; ui_confirm 'ok?'" <<< 'n' 2>/dev/null && rc=0 || rc=1; [ "$rc" -eq 1 ]
}

@test "ui_choose (plain): selects the option by number" {
  src="source '$PROJECT_ROOT/setup.sh'"
  v="$(KGUARD_PLAIN=1 bash -c "$src; ui_choose 'pick:' alpha beta gamma" <<< '2' 2>/dev/null)"
  [ "$v" = "beta" ]
}

@test "plain-interactive setup (no gum) installs + writes config from typed answers" {
  tb="$(_toolbox qemu-system-x86_64 qemu-img socat)"
  nest="$BATS_TEST_TMPDIR/nested"; echo Y > "$nest"
  cfg="$BATS_TEST_TMPDIR/pi.conf"; export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # answers: choose ~/.local/bin (opt 2), KGUARD_HOME, KGUARD_STAGE, confirm-install y, set-pass n
  run env -i PATH="$tb" HOME="$HOME" KGUARD_PLAIN=1 KGUARD_NESTING_FILE="$nest" KGUARD_CONFIG="$cfg" \
        bash "$PROJECT_ROOT/setup.sh" <<< $'2\n/srv/state\n/srv/images\ny\nn\n'
  [ "$status" -eq 0 ]
  [ -L "$HOME/.local/bin/kguard" ]
  grep -q 'KGUARD_HOME:=/srv/state' "$cfg"
}
