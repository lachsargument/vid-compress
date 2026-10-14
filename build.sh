#!/bin/bash
set -e

APP_NAME="VideoCompressor"
BUNDLE_ID="Salmonization.VideoCompressor"
APP_VERSION="1.0"

APP_BUNDLE="${APP_NAME}.app"
MACOS_DIR="${APP_BUNDLE}/Contents/MacOS"

rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}"
swiftc -O main.swift Core.swift -o "${MACOS_DIR}/${APP_NAME}"

cat <<PLIST > "${APP_BUNDLE}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>Video Compressor</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "=> Built ${APP_BUNDLE}"
