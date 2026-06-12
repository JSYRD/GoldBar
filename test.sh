#!/bin/bash
#
# GoldBar Test Runner
#
# Usage:
#   ./test.sh             — unit tests only (no network)
#   ./test.sh --all       — unit + integration tests (needs API key + network)
#   ./test.sh --verbose   — show per-test output
#
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$PROJECT_ROOT/Sources"
TEST_DIR="$PROJECT_ROOT/Tests"
BUILD_DIR="$PROJECT_ROOT/build"

# ── Source files (without main.swift) ──
SRC_FILES=(
    "$SOURCE_DIR/Preferences.swift"
)

# ── Test files ──
TEST_FILES=(
    "$TEST_DIR/TestHelpers.swift"
    "$TEST_DIR/PreferencesTests.swift"
    "$TEST_DIR/PriceCalcTests.swift"
    "$TEST_DIR/ColorSchemeTests.swift"
    "$TEST_DIR/APITests.swift"
    "$TEST_DIR/main.swift"
)

ALL_FILES=("${SRC_FILES[@]}" "${TEST_FILES[@]}")

echo "🧪 Building test suite (${#ALL_FILES[@]} files)..."

SDK_PATH=$(xcrun --show-sdk-path --sdk macosx 2>/dev/null || echo "")

if [ -n "$SDK_PATH" ]; then
    SDK_FLAGS="-sdk $SDK_PATH"
else
    SDK_FLAGS=""
fi

TEST_BIN="$BUILD_DIR/goldbar-tests"

swiftc -Onone -g \
    -target arm64-apple-macos13.0 \
    $SDK_FLAGS \
    -framework Foundation \
    -o "$TEST_BIN" \
    "${ALL_FILES[@]}"

echo "✅ Built: $TEST_BIN"
echo ""

# ── Run ──
"$TEST_BIN" "$@"
