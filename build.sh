#!/bin/bash
# Builds "C200 Controller.app" into ./build.
#   ./build.sh           build the app bundle
#   ./build.sh install   also copy it to ~/Applications
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="C200 Controller"
EXECUTABLE="C200Controller"
BUNDLE_ID="com.nathansherburn.c200controller"
APP="build/$APP_NAME.app"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchAgents"
cp "$BIN_DIR/$EXECUTABLE" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp "Resources/$BUNDLE_ID.agent.plist" "$APP/Contents/Library/LaunchAgents/"
[[ -f Resources/AppIcon.icns ]] || swift Scripts/make-icon.swift .
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# Ad-hoc signature: enough for camera access and the login item on this Mac.
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/$APP_NAME.app"
    ditto "$APP" "$HOME/Applications/$APP_NAME.app"
    echo "Installed to ~/Applications/$APP_NAME.app"
fi
