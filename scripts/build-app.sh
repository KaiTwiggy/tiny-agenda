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

# Sparkle (SPM binary target) must be embedded in the app bundle.
mkdir -p "$APP/Contents/Frameworks"
SPARKLE_SRC=""
while IFS= read -r -d '' f; do SPARKLE_SRC="$f"; break; done < <(
  find "$ROOT/.build" \( -path "*release*" -o -path "*Release*" \) -type d -name "Sparkle.framework" -print0 2>/dev/null
)
if [[ -z "${SPARKLE_SRC}" ]]; then
  XCFW="$(find "$ROOT/.build" -type d -name "Sparkle.xcframework" 2>/dev/null | head -1 || true)"
  if [[ -n "${XCFW}" ]]; then
    for slice in "macos-arm64_x86_64" "macos-arm64" "macos-x86_64"; do
      if [[ -d "${XCFW}/${slice}/Sparkle.framework" ]]; then
        SPARKLE_SRC="${XCFW}/${slice}/Sparkle.framework"
        break
      fi
    done
  fi
fi
if [[ -z "${SPARKLE_SRC}" ]]; then
  echo "error: Sparkle.framework not found under .build after swift build (check Package.swift Sparkle dependency)." >&2
  exit 1
fi
rsync -a "$SPARKLE_SRC" "$APP/Contents/Frameworks/"
# Ad-hoc sign embedded frameworks first, then the app (Sparkle XPC helpers live inside the framework).
while IFS= read -r -d '' f; do
  codesign --force --sign - "$f" 2>/dev/null || true
done < <(find "$APP/Contents/Frameworks" -type f -perm +111 -print0 2>/dev/null || true)
codesign --force --sign - "$APP/Contents/Frameworks/Sparkle.framework" 2>/dev/null || {
  echo "Note: codesign Sparkle.framework failed." >&2
}

# Ad-hoc sign the bundle so AMFI gets a valid signature (helps Keychain trust stability).
codesign --force --deep --sign - "$APP" 2>/dev/null || {
  echo "Note: codesign failed (install Xcode CLT). The app may trigger extra Keychain prompts." >&2
}
echo "Built: $APP"
echo "Run: open \"$APP\""
