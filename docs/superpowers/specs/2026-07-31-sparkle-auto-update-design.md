# Sparkle 자동 업데이트 설계

## 목표

Hot Target의 공개 GitHub 저장소 `kargnas/hottarget`에서 notarized DMG와 `appcast.xml`을 인증 없이 제공한다. 앱은 Sparkle 2로 EdDSA 서명을 검증하고, 릴리즈 빌드에서 하루 한 번 업데이트를 확인해 다운로드한 뒤 앱 종료 시 설치한다. `main` push, `vMAJOR.MINOR.PATCH` tag push, 수동 dispatch를 하나의 GitHub Actions workflow가 처리한다.

## 확정 사항

- 저장소와 release asset host: public `kargnas/hottarget`
- updater: Sparkle `2.8.1` exact pin
- feed: `https://github.com/kargnas/hottarget/releases/latest/download/appcast.xml`
- build/release: 기존 `direct-release` GitHub Environment와 Developer ID/App Store Connect API secrets 재사용
- 새 secret: Sparkle private EdDSA key를 담는 `SPARKLE_PRIVATE_KEY`
- 자동 release: `main` push 후 10분 debounce, patch bump
- 첫 release: tag가 없으므로 기존 앱 버전 `1.8.2` 다음인 `v1.8.3`
- 수동 release: workflow dispatch에서 patch/minor/major 선택
- source, package, scripts, tests, workflow가 바뀐 main push만 자동 release 대상으로 삼고 documentation-only push는 제외한다.

## 앱 통합

`Package.swift`는 Sparkle 2.8.1을 exact dependency로 추가하고 `HotTarget` executable만 Sparkle product에 의존한다. `AppDelegate`는 앱 수명 동안 `SPUStandardUpdaterController`를 strong reference로 유지한다. bare `swift run`에서는 `Bundle.main.bundlePath`가 `.app`이 아니므로 updater를 시작하지 않는다.

상태 메뉴 하단에는 updater가 준비된 bundle에서만 `Check for Updates…`를 표시한다. 선택 시 accessory app을 foreground로 활성화한 뒤 Sparkle UI를 연다. 현재 앱은 termination을 취소하는 delegate를 구현하지 않으므로 별도의 relaunch override는 필요하지 않다.

릴리즈 Info.plist에는 feed URL, public EdDSA key, 하루 간격, automatic checks/update 활성화를 기록한다. 개발 bundle은 같은 feed와 public key를 포함해 manual check는 지원하지만 automatic checks/update는 비활성화하여 로컬 앱이 release로 덮어써지는 일을 막는다.

## 패키징과 서명

두 bundle script는 SwiftPM 산출물의 `Sparkle.framework`를 `Contents/Frameworks`에 embed하고 앱 executable에 `@executable_path/../Frameworks` rpath가 없을 때 추가한다. release packaging은 다음 순서로 inside-out 서명한다.

1. Sparkle framework의 Autoupdate executable과 Updater.app
2. Downloader.xpc는 entitlement를 보존하고, Installer.xpc도 각각 서명
3. Sparkle.framework
4. Hot Target privileged helper
5. Hot Target.app

모든 release nested executable과 bundle은 Developer ID, hardened runtime, trusted timestamp를 사용한다. `--deep` signing은 사용하지 않고 마지막 검증에만 `codesign --verify --deep --strict`를 사용한다. 개발 build는 동일한 구조를 로컬 identity와 timestamp 없이 서명한다.

앱 bundle을 ZIP으로 제출해 notarize/staple한 다음, clean staging directory에 앱과 `/Applications` symlink만 담아 compressed DMG를 만든다. DMG도 Developer ID로 서명하고 notarize/staple한다. Staple까지 끝난 최종 DMG에 Sparkle EdDSA signature를 계산해야 파일 변경으로 signature가 무효화되지 않는다.

## 단일 release workflow

`.github/workflows/release-direct.yml` 하나가 다음 event를 받는다.

- `push.tags: v*`: tag version과 해당 commit을 release
- `push.branches: main`: 10분 대기 후 latest main을 patch release
- `workflow_dispatch`: patch/minor/major 입력으로 latest main을 release

`prepare` job만 main debounce concurrency group에 들어가며 `cancel-in-progress: true`를 사용한다. 새 push는 대기 중인 이전 run만 취소하고, 이미 notarization을 시작한 `release` job은 취소하지 않는다. prepare job은 `[skip release]`, 이미 tag된 HEAD, release 대상 path가 없는 push를 건너뛴다.

최신 strict semver tag를 기준으로 version을 계산하고, tag가 하나도 없으면 `1.8.2`를 baseline으로 쓴다. release job은 prepare output의 exact commit SHA를 checkout한다. `CFBundleShortVersionString`은 semantic version이고, `CFBundleVersion`과 appcast `sparkle:version`은 같은 단조 증가 정수 build number를 쓴다. appcast에는 `sparkle:shortVersionString`, DMG byte length, final EdDSA signature, tag-specific DMG URL을 기록한다.

Tag event는 기존 tag를 검증한다. Main/dispatch event는 모든 build, signing, notarization, staple, signature 생성이 성공한 뒤 `gh release create --target <commit>`로 tag와 release를 원자적으로 게시한다. 같은 tag의 release가 이미 있으면 asset을 idempotently 교체한다. GitHub token으로 생성한 tag는 별도 push workflow를 재귀 실행하지 않는다.

Release assets는 다음 세 개다.

- `Hot-Target-<version>.dmg`
- `Hot-Target-<version>.dmg.sha256`
- `appcast.xml`

## 키 관리

Sparkle `generate_keys --account "Hot Target"`로 전용 keypair를 만든다. private key의 canonical copy는 login keychain에 유지하고 CI export 파일은 GitHub `direct-release` Environment의 `SPARKLE_PRIVATE_KEY`로 stdin 등록한 직후 삭제한다. public key만 source에 들어간다. 기존 single-identity Developer ID P12와 App Store Connect API key secrets는 그대로 사용하며 Apple ID/app-specific password는 추가하지 않는다.

## 저장소 rename 반영

local `origin`을 `https://github.com/kargnas/hottarget.git`로 바꾸고 README, release runbook, appcast URL의 이전 저장소 주소를 모두 canonical URL로 교체한다. 사용자 소유 `.vscode/`는 stage하거나 commit하지 않는다.

## 오류 처리와 안전장치

- dependency, framework, public/private update key, signing identity 중 하나라도 없으면 release는 fail hard한다.
- ad-hoc signing fallback은 두지 않는다.
- malformed tag, 이미 존재하는 dispatch tag, non-monotonic version은 publish 전에 거부한다.
- temporary keychain, P12, P8, Sparkle private key는 `always()` cleanup에서 삭제한다.
- repository history credential marker scan이 깨끗한 상태만 유지한다.

## 검증

1. release contract test를 먼저 RED로 확장해 Sparkle dependency, app metadata, nested signing, DMG, appcast, main debounce 계약을 고정한다.
2. `swift test`와 release configuration tests를 통과시킨다.
3. `actionlint`, YAML parse, `shellcheck`, `git diff --check`를 통과시킨다.
4. 로컬 Developer ID package smoke에서 universal app/helper, embedded Sparkle framework, strict codesign, Info.plist release/dev gating을 확인한다.
5. 가능한 경우 test DMG 생성과 codesign까지 검증하되 실제 Apple notarization과 GitHub Release 생성은 workflow에서 수행한다.
6. main push 후 remote workflow file과 run 상태를 확인한다. 최초 release 완료 후 unauthenticated appcast fetch, DMG Gatekeeper/staple, Sparkle log의 EdDSA 성공을 확인한다.
