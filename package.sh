#!/bin/bash
#
# GoldBar DMG Packager
#
# Usage:
#   ./package.sh              — build release + create DMG
#   ./package.sh --skip-build — skip build, just re-pack existing .app
#
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
APP_BUNDLE="$BUILD_DIR/GoldBar.app"
RESOURCES_DIR="$PROJECT_ROOT/Resources"

# Read version from Info.plist
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$RESOURCES_DIR/Info.plist" 2>/dev/null || echo "0.0.0")
DMG_NAME="GoldBar-${VERSION}"
DIST_DIR="$BUILD_DIR/dist"
DMG_PATH="$BUILD_DIR/${DMG_NAME}.dmg"

echo "📦 Packaging GoldBar v$VERSION"

# ── Step 1: Build release ──────────────────────────────
if [ "${1:-}" != "--skip-build" ]; then
    echo ""
    echo "🔨 Building release..."
    "$PROJECT_ROOT/build.sh" release
fi

# ── Step 2: Prepare dist directory ─────────────────────
echo ""
echo "📁 Preparing dist..."

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

cp -R "$APP_BUNDLE" "$DIST_DIR/"

# Create Applications shortcut (standard DMG convention)
ln -s /Applications "$DIST_DIR/Applications"

# ── Step 3: Copy background image if present ────────────
if [ -f "$RESOURCES_DIR/dmg-background.png" ]; then
    mkdir -p "$DIST_DIR/.background"
    cp "$RESOURCES_DIR/dmg-background.png" "$DIST_DIR/.background/background.png"
    HAS_BG=true
else
    HAS_BG=false
    echo "  ℹ️  No dmg-background.png found (optional)"
fi

# ── Step 4: Create DMG ──────────────────────────────────
echo ""
echo "💿 Creating DMG..."

# Remove old DMG if exists
rm -f "$DMG_PATH"

# Create the DMG
hdiutil create \
    -volname "GoldBar" \
    -srcfolder "$DIST_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH"

# ── Step 5: Apply window layout (icon positions) ────────
if [ "$HAS_BG" = true ]; then
    echo "  🖼️  Applying background + icon layout..."

    # Mount the DMG
    MOUNT_DIR=$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_PATH" | \
        grep "Volumes/GoldBar" | awk '{print $NF}')

    if [ -n "$MOUNT_DIR" ]; then
        # Set background
        osascript -e "
            tell application \"Finder\"
                set dmg to disk \"GoldBar\"
                open dmg
                tell container window of dmg
                    set current view to icon view
                    set toolbar visible to false
                    set statusbar visible to false
                    set bounds to {100, 100, 640, 460}
                    set theViewOptions to the icon view options
                    set arrangement of theViewOptions to not arranged
                    set background picture of theViewOptions to file \".background:background.png\"
                    set position of item \"GoldBar.app\" to {160, 170}
                    set position of item \"Applications\" to {380, 170}
                end tell
                update dmg without registering applications
                delay 1
                close dmg
                eject dmg
            end tell
        " 2>/dev/null || true

        # Wait for eject
        sleep 2
    fi
fi

# ── Step 6: Result ──────────────────────────────────────
DMG_SIZE=$(du -sh "$DMG_PATH" | cut -f1)

echo ""
echo "═══════════════════════════════════════"
echo "✅ DMG created: $DMG_NAME.dmg"
echo "   Size: $DMG_SIZE"
echo "   Location: $DMG_PATH"
echo ""
echo "   SHA256:"
shasum -a 256 "$DMG_PATH"
echo "═══════════════════════════════════════"
