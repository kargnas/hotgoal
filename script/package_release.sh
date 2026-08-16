#!/bin/bash
set -euo pipefail

APP_NAME="hot-goal-for-mac"
APP_DISPLAY_NAME="Hot Goal for Mac"
BUNDLE_ID="as.kargn.hotgoalformac"
HELPER_NAME="hot-goal-for-mac-helper"
HELPER_ID="as.kargn.hotgoalformac.helper"
HELPER_PLIST_NAME="$HELPER_ID.plist"
ICON_NAME="HotGoalForMac"
MIN_SYSTEM_VERSION="14.0"
SPARKLE_PUBLIC_KEY="6skMx+nj9R6w4kS1Ct4GAi+z01EaSaZnEbnZ20QJcqo="
SPARKLE_FEED_URL="https://github.com/kargnas/hot-goal-for-mac/releases/latest/download/appcast.xml"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist-release}"

fail() {
  echo "release packaging failed: $*" >&2
  exit 1
}

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "VERSION must be semantic version x.y.z"
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || fail "BUILD_NUMBER must be a positive integer"
[[ "$SIGNING_IDENTITY" == "Developer ID Application:"* ]] || fail "SIGNING_IDENTITY must be a Developer ID Application identity"
[[ "$OUTPUT_DIR" != "/" && "$OUTPUT_DIR" != "$HOME" && "$OUTPUT_DIR" != "$ROOT_DIR" ]] || fail "unsafe OUTPUT_DIR"

swift build --package-path "$ROOT_DIR" -c release --arch arm64 --arch x86_64 --product "$APP_NAME"
swift build --package-path "$ROOT_DIR" -c release --arch arm64 --arch x86_64 --product "$HELPER_NAME"
BUILD_DIR="$(swift build --package-path "$ROOT_DIR" -c release --arch arm64 --arch x86_64 --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"
BUILD_HELPER="$BUILD_DIR/$HELPER_NAME"
BUILD_SPARKLE_FRAMEWORK="$BUILD_DIR/Sparkle.framework"
[[ -d "$BUILD_SPARKLE_FRAMEWORK" ]] || fail "missing Sparkle framework: $BUILD_SPARKLE_FRAMEWORK"

for binary in "$BUILD_BINARY" "$BUILD_HELPER"; do
  [[ -x "$binary" ]] || fail "missing built binary: $binary"
  archs="$(lipo -archs "$binary")"
  [[ " $archs " == *" arm64 "* && " $archs " == *" x86_64 "* ]] || fail "binary is not universal: $binary ($archs)"
done

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hot-goal-for-mac-release.XXXXXX")"
cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

APP_BUNDLE="$STAGING_DIR/$APP_DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_LAUNCH_DAEMONS="$APP_CONTENTS/Library/LaunchDaemons"
APP_BINARY="$APP_MACOS/$APP_NAME"
SPARKLE_FRAMEWORK="$APP_FRAMEWORKS/Sparkle.framework"
HELPER_BINARY="$APP_RESOURCES/$HELPER_NAME"
HELPER_PLIST="$APP_LAUNCH_DAEMONS/$HELPER_PLIST_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ARCHIVE_NAME="Hot-Goal-for-Mac-$VERSION.zip"
ARCHIVE="$STAGING_DIR/$ARCHIVE_NAME"

mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_FRAMEWORKS" "$APP_LAUNCH_DAEMONS"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$BUILD_HELPER" "$HELPER_BINARY"
/usr/bin/ditto "$BUILD_SPARKLE_FRAMEWORK" "$SPARKLE_FRAMEWORK"
chmod 755 "$APP_BINARY" "$HELPER_BINARY"
if ! otool -l "$APP_BINARY" | awk '/LC_RPATH/{found=1} found && /path @executable_path\/..\/Frameworks/{matched=1} END{exit matched ? 0 : 1}'; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY"
fi

ICONSET_DIR="$STAGING_DIR/$ICON_NAME.iconset"
swift "$ROOT_DIR/script/make_icon.swift" "$ICONSET_DIR"
iconutil --convert icns "$ICONSET_DIR" --output "$APP_RESOURCES/$ICON_NAME.icns"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>$ICON_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>SUFeedURL</key>
  <string>$SPARKLE_FEED_URL</string>
  <key>SUPublicEDKey</key>
  <string>$SPARKLE_PUBLIC_KEY</string>
  <key>SUScheduledCheckInterval</key>
  <integer>86400</integer>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUAutomaticallyUpdate</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

cat >"$HELPER_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$HELPER_ID</string>
  <key>MachServices</key>
  <dict>
    <key>$HELPER_ID</key>
    <true/>
  </dict>
  <key>BundleProgram</key>
  <string>Contents/Resources/$HELPER_NAME</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
</dict>
</plist>
PLIST

plutil -lint "$INFO_PLIST" "$HELPER_PLIST"
sign_sparkle_framework() {
  local framework="$1"
  local sparkle="$framework/Versions/B"

  codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$sparkle/Autoupdate"
  codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$sparkle/Updater.app"
  codesign --force --options runtime --timestamp \
    --preserve-metadata=entitlements \
    --sign "$SIGNING_IDENTITY" \
    "$sparkle/XPCServices/Downloader.xpc"
  codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$sparkle/XPCServices/Installer.xpc"
  codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$framework"
}

sign_sparkle_framework "$SPARKLE_FRAMEWORK"
codesign --force --options runtime --timestamp \
  --identifier "$HELPER_ID" \
  --sign "$SIGNING_IDENTITY" \
  "$HELPER_BINARY"
codesign --force --options runtime --timestamp \
  --sign "$SIGNING_IDENTITY" \
  "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

main_team="$(codesign -dvv "$APP_BUNDLE" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2}')"
helper_team="$(codesign -dvv "$HELPER_BINARY" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2}')"
[[ -n "$main_team" && "$main_team" == "$helper_team" ]] || fail "app/helper TeamIdentifier mismatch"

/usr/bin/ditto -c -k --keepParent --sequesterRsrc "$APP_BUNDLE" "$ARCHIVE"
mkdir -p "$OUTPUT_DIR"
OUTPUT_APP="$OUTPUT_DIR/$APP_DISPLAY_NAME.app"
OUTPUT_ARCHIVE="$OUTPUT_DIR/$ARCHIVE_NAME"
rm -rf "$OUTPUT_APP"
rm -f "$OUTPUT_ARCHIVE"
mv "$APP_BUNDLE" "$OUTPUT_APP"
mv "$ARCHIVE" "$OUTPUT_ARCHIVE"

printf 'APP_BUNDLE=%s\n' "$OUTPUT_APP"
printf 'ARCHIVE=%s\n' "$OUTPUT_ARCHIVE"
printf 'VERSION=%s\n' "$VERSION"
printf 'BUILD_NUMBER=%s\n' "$BUILD_NUMBER"
printf 'TEAM_ID=%s\n' "$main_team"
