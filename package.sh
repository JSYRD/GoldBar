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

# ── Step 3: Check for background ─────────────────────
if [ -f "$RESOURCES_DIR/dmg-background.png" ]; then
    HAS_BG=true
else
    HAS_BG=false
    echo "  ℹ️  No dmg-background.png found (optional)"
fi

# ── Step 4: Create writable DMG, lay out, compress ─────
echo ""
echo "💿 Creating DMG..."

rm -f "$DMG_PATH"

RW_DMG="$BUILD_DIR/GoldBar-rw.dmg"
rm -f "$RW_DMG"

# 4a. Create read-write DMG from dist folder
hdiutil create \
    -srcfolder "$DIST_DIR" \
    -volname "GoldBar" \
    -format UDRW \
    -fs HFS+ \
    -ov \
    "$RW_DMG" > /dev/null

# 4b. Mount for layout customisation
hdiutil detach "/Volumes/GoldBar" -force -quiet 2>/dev/null || true
hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" > /dev/null
MOUNT_DIR="/Volumes/GoldBar"

# Remove the auto-copied symlink and re-create (ensures correct)
rm -f "$MOUNT_DIR/Applications" 2>/dev/null || true
ln -s /Applications "$MOUNT_DIR/Applications"

# 4d. Copy background + set layout, then unmount
if [ "$HAS_BG" = true ]; then
    echo "  🖼️  Applying background + icon layout..."
    mkdir -p "$MOUNT_DIR/.background"
    cp "$RESOURCES_DIR/dmg-background.png" "$MOUNT_DIR/.background/background.png"

    # Hide the background folder in Finder
    SetFile -a V "$MOUNT_DIR/.background" 2>/dev/null || true

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
        end tell
    " 2>/dev/null || true
fi

# Unmount before converting
hdiutil detach "/Volumes/GoldBar" -force -quiet 2>/dev/null || true
sleep 1

# 4e. Convert to compressed read-only DMG
echo "  🔐 Converting to compressed..."
hdiutil convert "$RW_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    -o "$DMG_PATH"

rm -f "$RW_DMG"

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
