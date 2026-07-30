# Hot Target Sparkle Auto-Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Sparkle 2.8.1 automatic updates, notarized DMG/appcast publishing, and debounced main-push releases to Hot Target.

**Architecture:** One GitHub Actions workflow has a `prepare` job for tag/main/manual version resolution and a dependent `release` job for build, signing, notarization, DMG creation, Sparkle signing, and publishing. The app embeds Sparkle in hand-built development and release bundles, while automatic checks are release-only.

**Tech Stack:** Swift 6, AppKit, SwiftPM, Sparkle 2.8.1, bash, GitHub Actions, Developer ID, notarytool, EdDSA

## Global Constraints

- Keep macOS minimum version 14.0 and bundle identifier `as.kargn.hottarget`.
- Pin Sparkle exactly to 2.8.1.
- Use public feed `https://github.com/kargnas/hottarget/releases/latest/download/appcast.xml`.
- Reuse the `direct-release` Environment and API-key notarization secrets; never add Apple ID credentials.
- Never stage or commit `.vscode/`, `.p12`, `.p8`, or exported Sparkle private keys.
- Never use `codesign --deep` for signing; only use deep mode for final verification.
- Preserve tag releases and add debounced main-push patch releases in the same workflow.

---

### Task 1: Lock the release and updater contracts

**Files:**
- Modify: `script/test_release_config.sh`
- Create: `script/test_sparkle_config.sh`

**Interfaces:**
- Consumes: `.github/workflows/release-direct.yml`, `Package.swift`, `Sources/HotTarget/AppDelegate.swift`, `script/package_release.sh`, `script/build_and_run.sh`
- Produces: executable contract tests that fail until every required Sparkle/release behavior exists

- [ ] Add assertions for exact Sparkle 2.8.1, `SPUStandardUpdaterController`, manual update action, public feed URL, release-only automatic flags, framework embedding, inside-out signing, DMG/appcast creation, main debounce, dispatch bump input, and `SPARKLE_PRIVATE_KEY`.
- [ ] Run `./script/test_sparkle_config.sh` and confirm it fails before implementation.
- [ ] Keep the existing direct-release contract assertions and extend their asset expectations from ZIP to DMG/appcast.
- [ ] Commit only the two test scripts as `test: Sparkle 릴리즈 계약 추가`.

### Task 2: Add the exact Sparkle dependency and dedicated EdDSA key

**Files:**
- Modify: `Package.swift`
- Create: `Package.resolved`
- Modify: GitHub Environment secret `SPARKLE_PRIVATE_KEY` outside Git

**Interfaces:**
- Produces: `.product(name: "Sparkle", package: "Sparkle")` for `HotTarget`; public key string for plist generation; private key available only to CI

- [ ] Add `.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.8.1")` and the Sparkle product dependency.
- [ ] Resolve and build the package to create `Package.resolved` and verify the resolved version is 2.8.1.
- [ ] Download the official Sparkle 2.8.1 tools archive to a temporary directory and verify the download URL is the official GitHub release.
- [ ] Run `generate_keys --account "Hot Target"`, export the private key to a mode-600 temporary file, and capture only the printed public key for source configuration.
- [ ] Register the private key through stdin as `SPARKLE_PRIVATE_KEY` in the `direct-release` Environment; verify the secret name only; delete the export and tools archive.
- [ ] Commit `Package.swift` and `Package.resolved` as `build: Sparkle 2.8.1 의존성 추가`.

### Task 3: Integrate the updater into the menu-bar app

**Files:**
- Modify: `Sources/HotTarget/AppDelegate.swift`
- Test: `script/test_sparkle_config.sh`

**Interfaces:**
- Produces: `startUpdaterIfBundled()` and `checkForUpdates(_:)`; a strong `SPUStandardUpdaterController` reference

- [ ] Import Sparkle and add a nullable updater controller property.
- [ ] Call `startUpdaterIfBundled()` after menu/status setup; guard on `.app` bundle path.
- [ ] Add `Check for Updates…` before Quit only when the updater exists, target it to `checkForUpdates(_:)`, activate the accessory app, and invoke Sparkle.
- [ ] Run `swift test` and `./script/test_sparkle_config.sh`; updater source assertions pass while packaging assertions remain red.
- [ ] Commit `AppDelegate.swift` as `feat: Sparkle 업데이트 확인 메뉴 추가`.

### Task 4: Embed and sign Sparkle in development and release bundles

**Files:**
- Modify: `script/package_release.sh`
- Modify: `script/build_and_run.sh`
- Modify: `script/test_sparkle_config.sh`

**Interfaces:**
- Inputs: `SPARKLE_PUBLIC_KEY`; release `VERSION`, `BUILD_NUMBER`, `SIGNING_IDENTITY`; `ENABLE_AUTOMATIC_UPDATES=1` for release
- Produces: bundles with `Contents/Frameworks/Sparkle.framework`, executable rpath, SU plist keys, correct development/release automatic flags

- [ ] Add fail-hard validation for `SPARKLE_PUBLIC_KEY` in release packaging.
- [ ] Locate the SwiftPM Sparkle framework deterministically, embed it with `ditto`, and add the Frameworks rpath only when absent.
- [ ] Emit `SUFeedURL`, `SUPublicEDKey`, `SUScheduledCheckInterval`, `SUEnableAutomaticChecks`, and `SUAutomaticallyUpdate` into both Info.plists; release uses true and development false.
- [ ] Add a shared-in-each-script deepest-first signing sequence for Autoupdate, Updater.app, Downloader.xpc with preserved entitlements, Installer.xpc, and Sparkle.framework before signing helper/app.
- [ ] Run the contract tests, `shellcheck`, `swift test`, and a local signed development bundle smoke verifying plist values, rpath, embedded framework, and strict signature.
- [ ] Commit both bundle scripts and the updated contract test as `build: Sparkle 프레임워크를 앱 번들에 포함`.

### Task 5: Convert the release workflow to one-event pipeline

**Files:**
- Modify: `.github/workflows/release-direct.yml`
- Modify: `script/test_release_config.sh`
- Modify: `script/test_sparkle_config.sh`

**Interfaces:**
- `prepare` outputs: `should_release`, `version`, `tag`, `build_number`, `commit_sha`
- `release` consumes outputs and the six `direct-release` secrets, publishes DMG/checksum/appcast

- [ ] Add main branch push and workflow dispatch bump choices while retaining `v*` tags.
- [ ] Implement a 10-minute prepare-job debounce only for main push with job-level concurrency and `cancel-in-progress: true`; skip `[skip release]` and already-tagged HEAD.
- [ ] Resolve latest strict semver tag with 1.8.2 fallback; main uses patch, dispatch uses selected bump, tag validates exact version.
- [ ] Checkout the exact prepare output SHA, run tests, import the existing P12/P8 and new Sparkle key, and package with automatic updates enabled.
- [ ] Notarize/staple the app, create a clean DMG containing app plus `/Applications`, sign/notarize/staple the DMG, then compute EdDSA signature.
- [ ] Generate valid RSS appcast XML containing build number, short version, byte length, signature, and tag-specific public DMG URL.
- [ ] Publish or replace `Hot-Target-<version>.dmg`, checksum, and `appcast.xml`; create missing tags with `--target <commit_sha>` only after all validation succeeds.
- [ ] Keep `always()` cleanup for keychain, P12, P8, and Sparkle key.
- [ ] Run both contract tests, Ruby YAML parse, `actionlint`, and `shellcheck`.
- [ ] Commit workflow and tests as `feat: main push 자동 업데이트 릴리즈 추가`.

### Task 6: Update canonical repository documentation

**Files:**
- Modify: `README.md`
- Modify: `docs/direct-release.md`
- Modify: Git local `origin` URL outside tracked files

**Interfaces:**
- Produces: canonical `kargnas/hottarget` clone/release/runbook URLs and updater behavior documentation

- [ ] Replace every old repository URL and clone directory name.
- [ ] Document DMG installation, daily automatic checks, manual Check for Updates, main debounce, manual bumps, and Sparkle key secret.
- [ ] Set local origin to `https://github.com/kargnas/hottarget.git` and verify fetch/push URLs.
- [ ] Run a repository-wide old-name search and markdown diff check.
- [ ] Commit the two docs as `docs: 자동 업데이트와 새 저장소 주소 반영`.

### Task 7: Validate, review, and push main

**Files:**
- Validate all changed files; do not modify `.vscode/`

**Interfaces:**
- Produces: green local tree and remote `main` containing the single workflow pipeline

- [ ] Run `swift test`, both release contract tests, `shellcheck`, YAML parse, `actionlint`, and `git diff --check`.
- [ ] Build a Developer ID release bundle with version 1.8.3 and a non-publishing output directory; verify universal app/helper, embedded Sparkle, release plist flags, strict codesign, and archive integrity.
- [ ] Review tracked files for private key markers and assert no `.p12`, `.p8`, private Sparkle export, or `.vscode/` is staged/tracked.
- [ ] Review all commits and working tree; fix only issues attributable to this implementation in focused commits.
- [ ] Push `main` normally to canonical origin, never force.
- [ ] Verify remote main SHA, workflow contents, Environment secret names, and Actions run status.
- [ ] If the main-push workflow completes during the session, fetch unauthenticated appcast and validate the published DMG signature/staple; otherwise report the live run URL and the remaining remote-only checks without claiming they passed.
