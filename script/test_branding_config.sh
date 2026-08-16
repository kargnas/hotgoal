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
require_text README.md 'https://github.com/kargnas/hot-goal/releases/latest'
require_text README.md '~/Library/Logs/hot-goal/'
require_text README.md '/Applications/Hot Goal.app/Contents/MacOS/hot-goal'
require_text README.md '~/Library/Preferences/as.kargn.hotgoal.plist'
require_text README.md 'git clone https://github.com/kargnas/hot-goal.git'

require_text docs/direct-release.md 'Hot Goal releases'
require_text docs/direct-release.md 'REPO=kargnas/hot-goal'
require_text docs/direct-release.md 'Hot-Goal-<version>.dmg'
require_text docs/direct-release.md 'hot-goal-sparkle-key'

require_text .vscode/launch.json '"target": "hot-goal"'
require_text .vscode/launch.json '"target": "hot-goal-helper"'
require_text .vscode/launch.json '"name": "Debug hot-goal"'
require_text .vscode/launch.json '"name": "Release hot-goal-helper"'
require_text .codex/environments/environment.toml 'name = "hot-goal"'

require_path Sources/HotGoal/HotGoalApp.swift
require_path Sources/HotGoalCore/FanControlModels.swift
require_path Sources/HotGoalHelper/main.swift
require_text Package.swift 'name: "hot-goal"'
require_text Sources/HotGoalCore/FanControlModels.swift 'as.kargn.hotgoal'
require_text Sources/HotGoalHelper/main.swift 'hot-goal-helper'

if (( failures > 0 )); then
  printf 'Branding configuration check failed with %d issue(s).\n' "$failures"
  exit 1
fi

printf 'Branding configuration check passed.\n'
