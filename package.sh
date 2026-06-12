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

# 4a. Create blank read-write DMG
hdiutil create \
    -size 15m \
    -volname "GoldBar" \
    -fs HFS+ \
    -ov \
    "$RW_DMG" > /dev/null

# 4b. Mount + copy contents
hdiutil detach "/Volumes/GoldBar" -force -quiet 2>/dev/null || true
hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" > /dev/null
MOUNT_DIR="/Volumes/GoldBar"

cp -R "$DIST_DIR"/GoldBar.app "$MOUNT_DIR/"

# 4d. Create Applications alias (Finder alias, not symlink — shows folder icon)
APP_LINK_NAME="Applications"
case "$(defaults read -g AppleLocale 2>/dev/null | cut -d_ -f1)" in
    zh) APP_LINK_NAME="应用程序" ;;
    ko) APP_LINK_NAME="응용 프로그램" ;;
    *)  APP_LINK_NAME="Applications" ;;
esac

rm -rf "$MOUNT_DIR/$APP_LINK_NAME" 2>/dev/null || true
# macOS 26 Finder bug: symlinks show dashed icon. Fix: Finder alias + custom-icon bit.
osascript -e "
    tell application \"Finder\"
        make new alias file at disk \"GoldBar\" to folder (POSIX file \"/Applications\") with properties {name:\"${APP_LINK_NAME}\"}
    end tell
" 2>/dev/null
SetFile -a C "$MOUNT_DIR/$APP_LINK_NAME" 2>/dev/null || true

if [ "$HAS_BG" = true ]; then
    echo "  🖼️  Applying background + icon layout..."
    mkdir -p "$MOUNT_DIR/.background"
    cp "$RESOURCES_DIR/dmg-background.png" "$MOUNT_DIR/.background/background.png"
    SetFile -a V "$MOUNT_DIR/.background" 2>/dev/null || true

    osascript -e "
        tell application \"Finder\"
            set vol to disk \"GoldBar\"
            open vol
            set w to container window of vol
            set toolbar visible of w to false
            set statusbar visible of w to false
            set current view of w to icon view
            set bounds of w to {50, 50, 1130, 810}
            set opts to icon view options of w
            set arrangement of opts to not arranged
            set icon size of opts to 128
            set background picture of opts to file \".background:background.png\" of vol
            set position of item \"GoldBar.app\" of w to {265, 350}
            set position of item \"${APP_LINK_NAME}\" of w to {825, 350}
            update vol without registering applications
            delay 0.5
            close w
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
