#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

failures=0

fail() {
  printf 'FAIL: %s\n' "$1"
  failures=$((failures + 1))
}

require_text() {
  local file=$1
  local expected=$2
  if ! timeout 30s rg -n -F -- "$expected" "$file" >/dev/null; then
    fail "$file is missing: $expected"
  fi
}

require_path() {
  local path=$1
  if [[ ! -e "$path" ]]; then
    fail "missing path: $path"
  fi
}

require_text README.md '# Hot Goal for Mac'
require_text README.md 'https://github.com/kargnas/hot-goal-for-mac/releases/latest'
require_text README.md '~/Library/Logs/hot-goal-for-mac/'
require_text README.md '/Applications/Hot Goal for Mac.app/Contents/MacOS/hot-goal-for-mac'
require_text README.md '~/Library/Preferences/as.kargn.hotgoalformac.plist'
require_text README.md 'git clone https://github.com/kargnas/hot-goal-for-mac.git'

require_text docs/direct-release.md 'Hot Goal for Mac releases'
require_text docs/direct-release.md 'REPO=kargnas/hot-goal-for-mac'
require_text docs/direct-release.md 'Hot-Goal-for-Mac-<version>.dmg'
require_text docs/direct-release.md 'hot-goal-for-mac-sparkle-key'

require_text .vscode/launch.json '"target": "hot-goal-for-mac"'
require_text .vscode/launch.json '"target": "hot-goal-for-mac-helper"'
require_text .vscode/launch.json '"name": "Debug hot-goal-for-mac"'
require_text .vscode/launch.json '"name": "Release hot-goal-for-mac-helper"'
require_text .codex/environments/environment.toml 'name = "hot-goal-for-mac"'

require_path Sources/HotGoalForMac/HotGoalForMacApp.swift
require_path Sources/HotGoalForMacCore/FanControlModels.swift
require_path Sources/HotGoalForMacHelper/main.swift
require_text Package.swift 'name: "HotGoalForMac"'
require_text Sources/HotGoalForMacCore/FanControlModels.swift 'as.kargn.hotgoalformac'
require_text Sources/HotGoalForMacHelper/main.swift 'hot-goal-for-mac-helper'

if (( failures > 0 )); then
  printf 'Branding configuration check failed with %d issue(s).\n' "$failures"
  exit 1
fi

printf 'Branding configuration check passed.\n'
