#!/bin/bash
#
# GoldBar Build Script
# Compiles the Swift source files and creates a macOS .app bundle.
#
# Usage:
#   ./build.sh          — debug build
#   ./build.sh release  — release build (optimized)
#   ./build.sh run      — build and run
#
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$PROJECT_ROOT/Sources"
RESOURCES_DIR="$PROJECT_ROOT/Resources"
BUILD_DIR="$PROJECT_ROOT/build"
APP_NAME="GoldBar"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
BINARY_PATH="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Determine build mode
MODE="${1:-debug}"
if [ "$MODE" = "release" ]; then
    SWIFT_FLAGS="-O -whole-module-optimization"
    echo "🔨 Building GoldBar (release)..."
else
    SWIFT_FLAGS="-Onone -g"
    echo "🔨 Building GoldBar (debug)..."
fi

# Ensure build directory exists
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# ── Compile ──────────────────────────────────────────────
SWIFT_FILES=(
    "$SOURCE_DIR/main.swift"
    "$SOURCE_DIR/AppDelegate.swift"
    "$SOURCE_DIR/Preferences.swift"
    "$SOURCE_DIR/GoldPriceService.swift"
    "$SOURCE_DIR/CurrencyService.swift"
    "$SOURCE_DIR/MenuBarController.swift"
    "$SOURCE_DIR/SettingsWindowController.swift"
    "$SOURCE_DIR/WebSocketService.swift"
    "$SOURCE_DIR/SetupWindowController.swift"
)

echo "  Compiling ${#SWIFT_FILES[@]} Swift files..."

# Check swiftc availability
if ! command -v swiftc &> /dev/null; then
    echo "❌ Error: swiftc not found. Install Xcode or Command Line Tools."
    exit 1
fi

# Determine SDK path
SDK_PATH=$(xcrun --show-sdk-path --sdk macosx 2>/dev/null || echo "")

if [ -n "$SDK_PATH" ]; then
    SDK_FLAGS="-sdk $SDK_PATH"
else
    SDK_FLAGS=""
fi

swiftc $SWIFT_FLAGS \
    -target arm64-apple-macos13.0 \
    $SDK_FLAGS \
    -framework AppKit \
    -framework Foundation \
    -o "$BINARY_PATH" \
    "${SWIFT_FILES[@]}"

echo "  ✅ Binary compiled successfully"

# ── Bundle ───────────────────────────────────────────────
echo "  Creating app bundle..."

# Copy Info.plist
cp "$RESOURCES_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Create PkgInfo
echo "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# ── Code sign (ad-hoc) ───────────────────────────────────
echo "  Signing (ad-hoc)..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true

echo ""
echo "✅ GoldBar.app built successfully!"
echo "   Location: $APP_BUNDLE"
echo ""
echo "   To run:   open '$APP_BUNDLE'"
echo "   Or:       ./build.sh run"

# ── Run if requested ─────────────────────────────────────
if [ "$MODE" = "run" ]; then
    echo ""
    echo "🚀 Launching GoldBar..."
    open "$APP_BUNDLE"
fi
