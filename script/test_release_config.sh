#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/release-direct.yml"
PACKAGER="$ROOT_DIR/script/package_release.sh"
RUNBOOK="$ROOT_DIR/docs/direct-release.md"

fail() {
  echo "release config test failed: $*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing ${1#"$ROOT_DIR"/}"
}

require_text() {
  local file="$1"
  local text="$2"
  grep -Fq -- "$text" "$file" || fail "${file#"$ROOT_DIR"/} must contain: $text"
}

require_file "$WORKFLOW"
require_file "$PACKAGER"
require_file "$RUNBOOK"

/bin/bash -n "$PACKAGER"

require_text "$WORKFLOW" "tags:"
require_text "$WORKFLOW" "- 'v*'"
require_text "$WORKFLOW" "branches:"
require_text "$WORKFLOW" "- main"
require_text "$WORKFLOW" "workflow_dispatch:"
require_text "$WORKFLOW" "contents: write"
require_text "$WORKFLOW" 'secrets.DEVELOPER_ID_APPLICATION_P12_BASE64'
require_text "$WORKFLOW" 'secrets.DEVELOPER_ID_APPLICATION_P12_PASSWORD'
require_text "$WORKFLOW" 'secrets.NOTARYTOOL_KEY_P8_BASE64'
require_text "$WORKFLOW" 'secrets.NOTARYTOOL_KEY_ID'
require_text "$WORKFLOW" 'secrets.NOTARYTOOL_ISSUER_ID'
require_text "$WORKFLOW" 'secrets.SPARKLE_PRIVATE_KEY'
require_text "$WORKFLOW" 'xcrun notarytool submit'
require_text "$WORKFLOW" 'xcrun stapler staple'
require_text "$WORKFLOW" 'xcrun stapler validate'
require_text "$WORKFLOW" 'hdiutil create'
require_text "$WORKFLOW" 'sign_update'
require_text "$WORKFLOW" 'appcast.xml'
require_text "$WORKFLOW" "Hot-Goal-for-Mac-\$VERSION.dmg"
require_text "$WORKFLOW" 'gh release create'
require_text "$WORKFLOW" 'script/package_release.sh'
require_text "$WORKFLOW" 'security delete-keychain'

if grep -Fq 'script/build_and_run.sh' "$WORKFLOW"; then
  fail "release workflow must not install or launch the app"
fi

require_text "$PACKAGER" 'VERSION'
require_text "$PACKAGER" 'BUILD_NUMBER'
require_text "$PACKAGER" 'SIGNING_IDENTITY'
require_text "$PACKAGER" '--arch arm64 --arch x86_64'
require_text "$PACKAGER" 'lipo -archs'
require_text "$PACKAGER" 'codesign --force --options runtime --timestamp'
require_text "$PACKAGER" 'codesign --verify --deep --strict'
require_text "$PACKAGER" 'ditto -c -k --keepParent'

if grep -Fq 'timestamp=none' "$PACKAGER"; then
  fail "release signatures must use a trusted timestamp"
fi

require_text "$ROOT_DIR/.gitignore" 'dist-release/'
require_text "$RUNBOOK" 'DEVELOPER_ID_APPLICATION_P12_BASE64'
require_text "$RUNBOOK" 'NOTARYTOOL_KEY_P8_BASE64'
require_text "$RUNBOOK" 'SPARKLE_PRIVATE_KEY'
require_text "$RUNBOOK" 'kargnas/hot-goal-for-mac'
require_text "$RUNBOOK" 'main'
require_text "$RUNBOOK" 'workflow_dispatch'
require_text "$RUNBOOK" 'DMG'
require_text "$RUNBOOK" 'appcast.xml'
require_text "$RUNBOOK" 'git tag -a v'

printf 'DIRECT_RELEASE_CONFIG_TEST_PASSED\n'
