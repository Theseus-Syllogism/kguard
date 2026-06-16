#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BINDIR="${KGUARD_BINDIR:-/usr/local/bin}"
mkdir -p "$BINDIR"   # e.g. ~/.local/bin may not exist yet (offered by the setup wizard)
chmod +x "$ROOT/bin/kguard" "$ROOT/bin/kguard-setpass"
ln -sf "$ROOT/bin/kguard"         "$BINDIR/kguard"
ln -sf "$ROOT/bin/kguard-setpass" "$BINDIR/kguard-setpass"
echo "Installed: $BINDIR/kguard, $BINDIR/kguard-setpass" >&2
echo "Next: kguard setup   # interactive, or: kguard-setpass && kguard start" >&2
