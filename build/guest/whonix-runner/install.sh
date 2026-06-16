#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BINDIR="${WHONIX_BINDIR:-/usr/local/bin}"
chmod +x "$ROOT/bin/whonix" "$ROOT/bin/whonix-setpass"
ln -sf "$ROOT/bin/whonix"         "$BINDIR/whonix"
ln -sf "$ROOT/bin/whonix-setpass" "$BINDIR/whonix-setpass"
echo "Installed: $BINDIR/whonix, $BINDIR/whonix-setpass" >&2
echo "Next: whonix-setpass   # set encryption password, then: whonix start" >&2
