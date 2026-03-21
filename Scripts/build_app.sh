#!/bin/bash
# ============================================================
# build_app.sh
# Baut Stashfix als echte macOS .app-Bundle
# ============================================================

set -e

APP_NAME="Stashfix"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_DIR="$HOME/Applications"
APP_BUNDLE="$APP_DIR/$APP_NAME.app"

echo "🔨 Baue $APP_NAME..."

# Release-Build
cd "$PROJECT_DIR"
swift build -c release

# App-Bundle Struktur anlegen
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Binary kopieren
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# steuer_confirm kompilieren und ins Bundle kopieren
CONFIRM_SRC="$PROJECT_DIR/Tools/steuer_confirm.swift"
CONFIRM_BIN="$PROJECT_DIR/.build/steuer_confirm"

echo "🔨 Kompiliere steuer_confirm..."
swiftc "$CONFIRM_SRC" \
    -o "$CONFIRM_BIN" \
    -framework SwiftUI \
    -framework AppKit \
    -framework PDFKit \
    -framework Foundation

cp "$CONFIRM_BIN" "$APP_BUNDLE/Contents/MacOS/steuer_confirm"
echo "✅ steuer_confirm ins Bundle kopiert"

# Icon ins Bundle kopieren
if [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "✅ Icon ins Bundle kopiert"
fi

# Info.plist erstellen
cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Stashfix</string>
    <key>CFBundleDisplayName</key>
    <string>Stashfix</string>
    <key>CFBundleIdentifier</key>
    <string>de.stashfix.app</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>Stashfix</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 Stashfix</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# App signieren (ad-hoc, kein Developer Account nötig)
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "✅ Fertig!"
echo "App liegt in: $APP_BUNDLE"
echo ""
echo "Starten mit:"
echo "open '$APP_BUNDLE'"
