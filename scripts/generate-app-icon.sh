#!/usr/bin/env bash
# Build Support/AppIcon.icns from scripts/RenderAppIcon.swift (no extra deps beyond Xcode swift).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_ICNS="$ROOT/Support/AppIcon.icns"
SET_DIR="$ROOT/Support/AppIcon.iconset"
MASTER="$SET_DIR/.master1024.png"

mkdir -p "$SET_DIR"
swift "$ROOT/scripts/RenderAppIcon.swift" "$MASTER"

mk() {
  local name="$1" w="$2" h="$3"
  sips -z "$h" "$w" "$MASTER" --out "$SET_DIR/$name" >/dev/null
}

mk icon_16x16.png 16 16
mk icon_16x16@2x.png 32 32
mk icon_32x32.png 32 32
mk icon_32x32@2x.png 64 64
mk icon_128x128.png 128 128
mk icon_128x128@2x.png 256 256
mk icon_256x256.png 256 256
mk icon_256x256@2x.png 512 512
mk icon_512x512.png 512 512
mk icon_512x512@2x.png 1024 1024

# PNG for notification attachments (same artwork as AppIcon).
TOAST="$ROOT/Support/ToastIcon.png"
sips -z 256 256 "$MASTER" --out "$TOAST" >/dev/null
echo "Wrote $TOAST"

rm -f "$MASTER"
iconutil -c icns "$SET_DIR" -o "$OUT_ICNS"
rm -rf "$SET_DIR"
echo "Wrote $OUT_ICNS"
