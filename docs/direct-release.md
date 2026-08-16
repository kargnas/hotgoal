# Direct release and Sparkle updates

Hot Goal for Mac releases are built by `.github/workflows/release-direct.yml`. One workflow handles three entry points:

- A code, package, script, test, or workflow push to `main` waits 10 minutes for more commits and then creates the next patch release. A newer main push cancels only the older waiting job.
- A `vMAJOR.MINOR.PATCH` tag push releases that exact tag and commit without waiting.
- A manual `workflow_dispatch` creates a patch, minor, or major release from the latest main commit.

The workflow runs tests, builds universal `arm64+x86_64` app and helper binaries, embeds Sparkle 2.8.1, signs every nested executable inside-out with Developer ID, notarizes and staples the app, creates and notarizes a DMG, signs the final DMG with Sparkle EdDSA, and publishes the DMG, SHA-256 checksum, and `appcast.xml` in a GitHub Release.

## Security boundary

Never commit a `.p12`, `.p8`, Sparkle private key, password, or provisioning profile. Signing and update credentials are GitHub Actions secrets in the `direct-release` Environment. The workflow writes them only under `$RUNNER_TEMP`, uses a temporary keychain, and deletes the keychain and files in an `always()` cleanup step.

The repository is public so Sparkle clients can fetch release assets without GitHub authentication. Secrets remain encrypted and are not exposed by public repository visibility. Environment deployment rules must allow both `main` and `v*` release tags.

## Required environment secrets

| Secret | Value |
|---|---|
| `DEVELOPER_ID_APPLICATION_P12_BASE64` | Base64 of a PKCS#12 containing exactly one Developer ID Application certificate/private-key identity. |
| `DEVELOPER_ID_APPLICATION_P12_PASSWORD` | Random password protecting that PKCS#12. |
| `NOTARYTOOL_KEY_P8_BASE64` | Base64 of an App Store Connect API private key authorized for notarization. |
| `NOTARYTOOL_KEY_ID` | App Store Connect API key ID. |
| `NOTARYTOOL_ISSUER_ID` | App Store Connect issuer ID. |
| `SPARKLE_PRIVATE_KEY` | Existing Base64 Ed25519 seed used to sign published updates. |

The Apple Team ID (`6YQH3QFFK8`), API key ID, issuer ID, certificate name, and Sparkle public key are identifiers rather than private key material. Apple ID and app-specific password secrets are not used.

## Prepare and verify credentials

1. Confirm a Developer ID Application identity is installed:

   ```bash
   security find-identity -p codesigning -v
   ```

2. Export identities into a temporary PKCS#12, isolate the intended Developer ID identity in a temporary keychain, and export a final PKCS#12 containing exactly that one identity. `security export -t identities` can export every private identity in a keychain, so never upload its unfiltered output.
3. Validate the App Store Connect API key before upload:

   ```bash
   xcrun notarytool history \
     --key AuthKey.p8 \
     --key-id "$NOTARYTOOL_KEY_ID" \
     --issuer "$NOTARYTOOL_ISSUER_ID"
   ```

4. Copy the deployed Sparkle seed from its secure backup to `$TMPDIR/hot-goal-for-mac-sparkle-key`. The workflow derives its public key and fails before publishing if it does not match the `SUPublicEDKey` embedded by the bundle scripts.

## Upload secrets

Write values through stdin so they do not appear in command history:

```bash
REPO=kargnas/hot-goal-for-mac
ENVIRONMENT=direct-release

base64 -i DeveloperIDApplication.p12 | \
  gh secret set DEVELOPER_ID_APPLICATION_P12_BASE64 --env "$ENVIRONMENT" --repo "$REPO"

cat DeveloperIDApplication.password | \
  gh secret set DEVELOPER_ID_APPLICATION_P12_PASSWORD --env "$ENVIRONMENT" --repo "$REPO"

base64 -i AuthKey.p8 | \
  gh secret set NOTARYTOOL_KEY_P8_BASE64 --env "$ENVIRONMENT" --repo "$REPO"

printf '%s' "$NOTARYTOOL_KEY_ID" | \
  gh secret set NOTARYTOOL_KEY_ID --env "$ENVIRONMENT" --repo "$REPO"
printf '%s' "$NOTARYTOOL_ISSUER_ID" | \
  gh secret set NOTARYTOOL_ISSUER_ID --env "$ENVIRONMENT" --repo "$REPO"

cat "$TMPDIR/hot-goal-for-mac-sparkle-key" | \
  gh secret set SPARKLE_PRIVATE_KEY --env "$ENVIRONMENT" --repo "$REPO"
```

Delete every export after names-only verification:

```bash
gh secret list --env direct-release --repo kargnas/hot-goal-for-mac
rm -f DeveloperIDApplication.p12 DeveloperIDApplication.password AuthKey.p8 \
  "$TMPDIR/hot-goal-for-mac-sparkle-key"
```

## Publish releases

A normal code push to main creates a patch release after the 10-minute debounce. Add `[skip release]` to the HEAD commit message when a qualifying push must not publish.

Push an exact version when required:

```bash
git tag -a v1.8.3 -m "Hot Goal for Mac 1.8.3"
git push origin v1.8.3
```

Run a manual bump from GitHub or with `gh`:

```bash
gh workflow run release-direct.yml --repo kargnas/hot-goal-for-mac -f bump=minor
```

The first automatic release falls back from the existing app version 1.8.2 to v1.8.3 when no prior semantic-version tag exists. Later releases use the highest strict semantic-version tag. `CFBundleVersion` and appcast `sparkle:version` use the same monotonic numeric build value.

After completion, verify workflow and release metadata:

```bash
gh run list --workflow release-direct.yml --repo kargnas/hot-goal-for-mac
gh release view v1.8.3 --repo kargnas/hot-goal-for-mac
curl -fsSL https://github.com/kargnas/hot-goal-for-mac/releases/latest/download/appcast.xml
```

Release assets are:

- `Hot-Goal-for-Mac-<version>.dmg`
- `Hot-Goal-for-Mac-<version>.dmg.sha256`
- `appcast.xml`

## End-to-end verification

```bash
curl -fsSLO https://github.com/kargnas/hot-goal-for-mac/releases/latest/download/Hot-Goal-for-Mac-1.8.3.dmg
spctl -a -t open --context context:primary-signature -v Hot-Goal-for-Mac-1.8.3.dmg
xcrun stapler validate Hot-Goal-for-Mac-1.8.3.dmg
/usr/bin/log show --last 3m \
  --predicate 'subsystem == "org.sparkle-project.Sparkle"' \
  --style compact
```

An update check should log that the EdDSA signature is correct. Release builds check daily and install downloaded updates when Hot Goal for Mac quits. Development bundles keep automatic checks and installation disabled but retain the manual **Check for Updates…** command.

## Local packaging check

The release packager never installs, launches, registers, or unregisters the app/helper. It writes only to `dist-release/`:

```bash
VERSION=1.8.3 \
BUILD_NUMBER=1008003 \
SIGNING_IDENTITY="Developer ID Application: Example Name (TEAMID)" \
./script/package_release.sh
```

Local packaging verifies the universal app/helper, embedded Sparkle framework, nested Developer ID signatures, release update metadata, and ZIP used for app notarization. Apple notarization, DMG creation, appcast generation, and GitHub Release publication remain workflow responsibilities.
