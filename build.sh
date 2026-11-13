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
SIGN_ID="C200 Controller Local Signing"

# A self-signed certificate in the login keychain, created on the first build. Signing
# with it (rather than ad-hoc) keeps the app's identity the same across rebuilds, so
# macOS keeps the camera permission.
ensure_signing_identity() {
    security find-identity -p codesigning | grep -q "\"$SIGN_ID\"" && return
    echo "Creating code signing certificate \"$SIGN_ID\" in the login keychain"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    cat > "$tmp/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $SIGN_ID
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
    # The system LibreSSL writes a PKCS#12 file that `security import` can read.
    /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$tmp/cert.cnf" \
        -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
    /usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
        -out "$tmp/id.p12" -passout pass:c200
    security import "$tmp/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
        -P c200 -T /usr/bin/codesign
}

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
[[ -f Resources/AppIcon.icns ]] || swift Scripts/make-icon.swift .
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

ensure_signing_identity
codesign --force --sign "$SIGN_ID" --identifier "$BUNDLE_ID" "$APP"
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/$APP_NAME.app"
    ditto "$APP" "$HOME/Applications/$APP_NAME.app"
    echo "Installed to ~/Applications/$APP_NAME.app"
fi
