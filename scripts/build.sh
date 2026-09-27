#!/usr/bin/env bash
#
# Build ColimaCommandCenter.app and install to ~/Applications.
# Ad-hoc signed, Spotlight-registered. No Apple Developer ID needed.
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Colima Command Center"
APP_DIR="$HOME/Applications/$APP_NAME.app"
BINARY_NAME="ColimaCommandCenter"

echo "== Building =="
swift build -c release 2>&1

BIN="$REPO_DIR/.build/release/$BINARY_NAME"
[ -x "$BIN" ] || { echo "ERROR: binary not found at $BIN"; exit 1; }

echo "== Assembling bundle =="
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN" "$APP_DIR/contents/MacOS/$BINARY_NAME"

# Embed icon if present
ICNS_SRC="$REPO_DIR/Resources/AppIcon.icns"
if [ -f "$ICNS_SRC" ]; then
    cp "$ICNS_SRC" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# Embed localization resources
for LPROJ in "$REPO_DIR"/Resources/*.lproj; do
    [ -d "$LPROJ" ] && cp -R "$LPROJ" "$APP_DIR/Contents/Resources/"
done

cat > "$APP_DIR/Contents/Info.plist" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>Colima Command Center</string>
  <key>CFBundleDisplayName</key>
  <string>Colima Command Center</string>
  <key>CFBundleExecutable</key>
  <string>ColimaCommandCenter</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>local.colima.command-center</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
XML

echo "== Codesign (ad-hoc) =="
codesign --force --sign - "$APP_DIR" 2>&1

echo "== Register with Spotlight =="
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
"$LSREGISTER" -f "$APP_DIR" 2>&1 || true

echo "== Done =="
echo "  Installed: $APP_DIR"
echo "  Spotlight: suche 'colima command'"
