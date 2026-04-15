#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)/TinyAgenda"
APP="$ROOT/TinyAgenda.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_PATH" "$APP/Contents/MacOS/TinyAgenda"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/TinyAgenda"
# Ad-hoc sign the bundle so AMFI gets a valid signature (helps Keychain trust stability).
codesign --force --deep --sign - "$APP" 2>/dev/null || {
    echo "Note: codesign failed (install Xcode CLT). The app may trigger extra Keychain prompts." >&2
}
echo "Built: $APP"
echo "Run: open \"$APP\""
