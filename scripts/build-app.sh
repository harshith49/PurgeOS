#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
arch="${1:-$(uname -m)}"
case "$arch" in arm64|x86_64) ;; *) echo 'Usage: scripts/build-app.sh [arm64|x86_64]' >&2; exit 1;; esac
swift build -c release --arch "$arch" --product PurgeOS
bin=$(swift build -c release --arch "$arch" --show-bin-path)
app="dist/$arch/PurgeOS.app"
mkdir -p "$app/Contents/MacOS"
cp "$bin/PurgeOS" "$app/Contents/MacOS/PurgeOS"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PurgeOS</string>
<key>CFBundleIdentifier</key><string>org.purgeos.app</string>
<key>CFBundleName</key><string>PurgeOS</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xattr -cr "$app"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
ditto -c -k --keepParent --norsrc "$app" "dist/$arch/PurgeOS.zip"
echo "Built $app and dist/$arch/PurgeOS.zip"
