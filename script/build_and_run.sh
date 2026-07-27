#!/bin/bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="ThermalIcon"
APP_DISPLAY_NAME="Thermal Icon"
BUNDLE_ID="as.kargn.ThermalIcon"
HELPER_NAME="ThermalIconFanHelper"
HELPER_ID="as.kargn.ThermalIcon.FanHelper"
HELPER_PLIST_NAME="$HELPER_ID.plist"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_DISPLAY_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

swift build --package-path "$ROOT_DIR"
BUILD_DIR="$(swift build --package-path "$ROOT_DIR" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"
BUILD_HELPER="$BUILD_DIR/$HELPER_NAME"

SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(security find-identity -p codesigning -v | awk -F'"' '/Developer ID Application:/ { print $2; exit }')"
fi
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(security find-identity -p codesigning -v | awk -F'"' '/Apple Development:/ { print $2; exit }')"
fi
if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "fan control requires a Developer ID Application or Apple Development signing identity" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
STAGING_DIR="$(mktemp -d "$DIST_DIR/.thermal-icon.XXXXXX")"
STAGING_APP_BUNDLE="$STAGING_DIR/$APP_DISPLAY_NAME.app"
STAGING_APP_CONTENTS="$STAGING_APP_BUNDLE/Contents"
STAGING_APP_MACOS="$STAGING_APP_CONTENTS/MacOS"
STAGING_APP_RESOURCES="$STAGING_APP_CONTENTS/Resources"
STAGING_APP_LAUNCH_DAEMONS="$STAGING_APP_CONTENTS/Library/LaunchDaemons"
STAGING_APP_BINARY="$STAGING_APP_MACOS/$APP_NAME"
STAGING_HELPER_BINARY="$STAGING_APP_RESOURCES/$HELPER_NAME"
STAGING_HELPER_PLIST="$STAGING_APP_LAUNCH_DAEMONS/$HELPER_PLIST_NAME"
STAGING_INFO_PLIST="$STAGING_APP_CONTENTS/Info.plist"
DEV_JOB_LABEL="$BUNDLE_ID.dev"
DEV_JOB_DOMAIN="gui/$(id -u)"
DEV_JOB_WAS_LOADED=false
DEV_JOB_STOPPED=false

restore_dev_job() {
  if [[ "$DEV_JOB_STOPPED" == true && -x "$APP_BINARY" ]]; then
    launchctl submit -l "$DEV_JOB_LABEL" -p "$APP_BINARY" -- "$APP_BINARY"
    DEV_JOB_STOPPED=false
  fi
}

cleanup() {
  rm -rf "$STAGING_DIR"
  if ! restore_dev_job; then
    echo "failed to restore $DEV_JOB_LABEL" >&2
  fi
}
trap cleanup EXIT

mkdir -p "$STAGING_APP_MACOS" "$STAGING_APP_RESOURCES" "$STAGING_APP_LAUNCH_DAEMONS"
cp "$BUILD_BINARY" "$STAGING_APP_BINARY"
cp "$BUILD_HELPER" "$STAGING_HELPER_BINARY"
chmod +x "$STAGING_APP_BINARY" "$STAGING_HELPER_BINARY"

cat >"$STAGING_INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>1.6.1</string>
  <key>CFBundleVersion</key>
  <string>12</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

cat >"$STAGING_HELPER_PLIST" <<PLIST
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

codesign --force --options runtime --timestamp=none \
  --identifier "$HELPER_ID" \
  --sign "$SIGNING_IDENTITY" \
  "$STAGING_HELPER_BINARY"
codesign --force --options runtime --timestamp=none \
  --sign "$SIGNING_IDENTITY" \
  "$STAGING_APP_BUNDLE"
codesign --verify --strict "$STAGING_HELPER_BINARY"
codesign --verify --strict "$STAGING_APP_BUNDLE"

HELPER_WAS_REGISTERED=false
if [[ -x "$APP_BINARY" ]]; then
  CURRENT_HELPER_STATUS="$("$STAGING_APP_BINARY" --helper-status)"
  case "$CURRENT_HELPER_STATUS" in
    "Fan helper: enabled"|"Fan helper: approval required") HELPER_WAS_REGISTERED=true ;;
  esac
fi

if launchctl print "$DEV_JOB_DOMAIN/$DEV_JOB_LABEL" >/dev/null 2>&1; then
  DEV_JOB_WAS_LOADED=true
  launchctl bootout "$DEV_JOB_DOMAIN/$DEV_JOB_LABEL"
  DEV_JOB_STOPPED=true
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
for _ in {1..50}; do
  if ! pgrep -x "$APP_NAME" >/dev/null; then
    break
  fi
  sleep 0.1
done
if pgrep -x "$APP_NAME" >/dev/null; then
  echo "failed to stop $APP_NAME before replacing its bundle" >&2
  exit 1
fi

if [[ "$HELPER_WAS_REGISTERED" == true ]]; then
  "$STAGING_APP_BINARY" --unregister-helper
  # BackgroundTaskManagement can reject an immediate re-registration after a successful unregister.
  sleep 2
fi

rm -rf "$APP_BUNDLE"
mv "$STAGING_APP_BUNDLE" "$APP_BUNDLE"

if [[ "$HELPER_WAS_REGISTERED" == true ]]; then
  "$APP_BINARY" --register-helper
fi

restore_dev_job

open_app() {
  if [[ "$DEV_JOB_WAS_LOADED" == false ]]; then
    /usr/bin/open -n "$APP_BUNDLE"
  fi
}

verify_process() {
  for _ in {1..20}; do
    if pgrep -x "$APP_NAME" >/dev/null; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --probe|probe)
    "$BUILD_BINARY" --print-temperature
    "$BUILD_BINARY" --print-fans
    ;;
  --helper-status|helper-status)
    "$APP_BINARY" --helper-status
    ;;
  --register-helper|register-helper)
    "$APP_BINARY" --register-helper
    ;;
  --verify|verify)
    open_app
    verify_process
    "$BUILD_BINARY" --print-temperature
    "$BUILD_BINARY" --print-fans
    "$APP_BINARY" --helper-status
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--probe|--helper-status|--register-helper|--verify]" >&2
    exit 2
    ;;
esac
