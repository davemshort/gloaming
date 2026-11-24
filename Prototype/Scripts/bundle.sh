#!/bin/zsh
# Builds DesktopPrototype and wraps it in a minimal, ad-hoc-signed .app bundle.
# Works with the Command Line Tools alone; no Xcode or signing identity required.
set -euo pipefail

cd "${0:A:h}/.."
CONFIG="${1:-release}"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/DesktopPrototype"

APP="build/DesktopPrototype.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/DesktopPrototype"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>         <string>DesktopPrototype</string>
    <key>CFBundleIdentifier</key>         <string>org.example.DesktopPrototype</string>
    <key>CFBundleName</key>               <string>DesktopPrototype</string>
    <key>CFBundlePackageType</key>        <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>0.1</string>
    <key>CFBundleVersion</key>            <string>1</string>
    <key>LSMinimumSystemVersion</key>     <string>14.0</string>
    <key>LSUIElement</key>                <true/>
    <key>NSHighResolutionCapable</key>    <true/>
</dict>
</plist>
PLIST

# Ad-hoc signature ("-") so Gatekeeper/TCC see a consistent identity locally.
codesign --force --sign - "$APP"
echo "Built $PWD/$APP"
