#!/bin/zsh
# Builds LidAwake.app and installs it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"
APP="build/LidAwake.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS"
swiftc -O main.swift -o "$APP/Contents/MacOS/LidAwake"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>LidAwake</string>
<key>CFBundleIdentifier</key><string>local.lidawake</string>
<key>CFBundleExecutable</key><string>LidAwake</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
EOF
codesign --force -s - "$APP"
pkill -x LidAwake 2>/dev/null || true
rm -rf /Applications/LidAwake.app
cp -R "$APP" /Applications/
echo "Installed /Applications/LidAwake.app"
