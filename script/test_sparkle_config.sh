#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="$ROOT_DIR/Package.swift"
APP_DELEGATE="$ROOT_DIR/Sources/HotGoal/AppDelegate.swift"
PACKAGER="$ROOT_DIR/script/package_release.sh"
DEV_BUILDER="$ROOT_DIR/script/build_and_run.sh"
WORKFLOW="$ROOT_DIR/.github/workflows/release-direct.yml"

fail() {
  echo "Sparkle config test failed: $*" >&2
  exit 1
}

require_text() {
  local file="$1"
  local text="$2"
  grep -Fq -- "$text" "$file" || fail "${file#"$ROOT_DIR"/} must contain: $text"
}

for file in "$PACKAGE" "$APP_DELEGATE" "$PACKAGER" "$DEV_BUILDER" "$WORKFLOW"; do
  [[ -f "$file" ]] || fail "missing ${file#"$ROOT_DIR"/}"
done

require_text "$PACKAGE" '.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.8.1")'
require_text "$PACKAGE" '.product(name: "Sparkle", package: "Sparkle")'

require_text "$APP_DELEGATE" 'import Sparkle'
require_text "$APP_DELEGATE" 'SPUStandardUpdaterController'
require_text "$APP_DELEGATE" 'startUpdaterIfBundled'
require_text "$APP_DELEGATE" 'Check for Updates…'
require_text "$APP_DELEGATE" 'checkForUpdates'
require_text "$APP_DELEGATE" 'NSApp.activate(ignoringOtherApps: true)'

for file in "$PACKAGER" "$DEV_BUILDER"; do
  require_text "$file" 'SPARKLE_PUBLIC_KEY'
  require_text "$file" 'Sparkle.framework'
  require_text "$file" '@executable_path/../Frameworks'
  require_text "$file" 'SUFeedURL'
  require_text "$file" 'https://github.com/kargnas/hot-goal/releases/latest/download/appcast.xml'
  require_text "$file" 'SUPublicEDKey'
  require_text "$file" 'SUEnableAutomaticChecks'
  require_text "$file" 'SUAutomaticallyUpdate'
  require_text "$file" 'Downloader.xpc'
  require_text "$file" '--preserve-metadata=entitlements'
done
require_text "$PACKAGER" '<true/>'
require_text "$DEV_BUILDER" '<false/>'

require_text "$WORKFLOW" 'branches:'
require_text "$WORKFLOW" '- main'
require_text "$WORKFLOW" 'workflow_dispatch:'
require_text "$WORKFLOW" 'sleep 600'
require_text "$WORKFLOW" 'cancel-in-progress:'
require_text "$WORKFLOW" "github.ref == 'refs/heads/main'"
require_text "$WORKFLOW" 'secrets.SPARKLE_PRIVATE_KEY'
require_text "$WORKFLOW" 'contents: read'
require_text "$WORKFLOW" 'contents: write'
require_text "$WORKFLOW" 'timeout-minutes: 90'
require_text "$WORKFLOW" 'hdiutil create'
require_text "$WORKFLOW" 'SIGN_UPDATE=".build/artifacts/sparkle/Sparkle/bin/sign_update"'
require_text "$WORKFLOW" 'SPARKLE_PRIVATE_KEY does not match SUPublicEDKey'
require_text "$WORKFLOW" 'sparkle:minimumSystemVersion'
require_text "$WORKFLOW" 'git fetch --force origin'
require_text "$WORKFLOW" 'appcast.xml'
require_text "$WORKFLOW" "Hot-Goal-\$VERSION.dmg"
require_text "$WORKFLOW" "releases/download/\$TAG/Hot-Goal-\$VERSION.dmg"

if grep -Fq -- 'codesign --deep' "$PACKAGER"; then
  fail "package_release.sh must not use codesign --deep for signing"
fi
if grep -Fq -- "'README.md'" "$WORKFLOW" || grep -Fq -- "'docs/**'" "$WORKFLOW"; then
  fail "documentation-only pushes must not publish an automatic app release"
fi
if grep -Fq -- 'Sparkle-2.8.1.tar.xz' "$WORKFLOW"; then
  fail "release workflow must use the checksum-verified SwiftPM sign_update artifact"
fi

printf 'SPARKLE_CONFIG_TEST_PASSED\n'
