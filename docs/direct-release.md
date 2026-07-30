# Direct release automation

Hot Target releases are built by `.github/workflows/release-direct.yml` whenever a `vMAJOR.MINOR.PATCH` tag is pushed. The workflow runs tests, builds universal `arm64+x86_64` app and helper binaries, signs both with Developer ID, submits the app to Apple notarization, staples the ticket, and creates a GitHub Release containing a ZIP and SHA-256 checksum.

## Security boundary

Never commit a `.p12`, `.p8`, private key, password, or provisioning profile. The signing certificate and notary key must be stored as GitHub Actions secrets in the `direct-release` environment. The workflow decodes them only into `$RUNNER_TEMP`, imports the certificate into a temporary keychain, and deletes both the files and keychain in an `always()` cleanup step.

Create a protected GitHub Environment named `direct-release`. Restrict deployment branches/tags to release tags and, if more than one person has write access, add a required reviewer or a ruleset that restricts creation of `v*` tags.

## Required environment secrets

| Secret | Value |
|---|---|
| `DEVELOPER_ID_APPLICATION_P12_BASE64` | Base64 of a PKCS#12 export containing the **Developer ID Application** certificate and its private key. |
| `DEVELOPER_ID_APPLICATION_P12_PASSWORD` | Password used when exporting that PKCS#12 file. |
| `NOTARYTOOL_KEY_P8_BASE64` | Base64 of an App Store Connect API private key (`.p8`) authorized for notarization. |
| `NOTARYTOOL_KEY_ID` | App Store Connect API key ID. |
| `NOTARYTOOL_ISSUER_ID` | App Store Connect issuer ID. |

The Apple Team ID (`6YQH3QFFK8`) and certificate name are identifiers, not private keys. Do not use an Apple Development certificate for a public release.

## Prepare the signing certificate

1. In Keychain Access, locate the **Developer ID Application** certificate together with its private key.
2. Export that identity as a password-protected `.p12` file.
3. Create an App Store Connect API key and download its `.p8` file. Apple only allows downloading it once.
4. Confirm the local identity before uploading anything:

   ```bash
   security find-identity -p codesigning -v
   ```

## Upload secrets

Authenticate `gh`, then write secrets directly to the GitHub Environment without creating tracked files:

```bash
REPO=kargnas/modern-mac-fan-control
ENVIRONMENT=direct-release

base64 -i DeveloperIDApplication.p12 | \
  gh secret set DEVELOPER_ID_APPLICATION_P12_BASE64 --env "$ENVIRONMENT" --repo "$REPO"

read -r -s -p "PKCS#12 password: " P12_PASSWORD; echo
printf '%s' "$P12_PASSWORD" | \
  gh secret set DEVELOPER_ID_APPLICATION_P12_PASSWORD --env "$ENVIRONMENT" --repo "$REPO"
unset P12_PASSWORD

base64 -i AuthKey.p8 | \
  gh secret set NOTARYTOOL_KEY_P8_BASE64 --env "$ENVIRONMENT" --repo "$REPO"

gh secret set NOTARYTOOL_KEY_ID --env "$ENVIRONMENT" --repo "$REPO"
gh secret set NOTARYTOOL_ISSUER_ID --env "$ENVIRONMENT" --repo "$REPO"
```

Delete the temporary export files after confirming the secrets exist:

```bash
rm -f DeveloperIDApplication.p12 AuthKey.p8
```

GitHub shows secret names but never returns their values:

```bash
gh secret list --env direct-release --repo kargnas/modern-mac-fan-control
```

## Publish a release

First reconcile and push the intended `main` history. This repository may have local and remote commits on both sides, so do not force-push or create a release tag until that divergence has been reviewed.

Create and push an annotated semantic-version tag:

```bash
git tag -a v1.8.3 -m "Hot Target 1.8.3"
git push origin v1.8.3
```

The tag starts the workflow automatically. `CFBundleShortVersionString` comes from the tag without the leading `v`; `CFBundleVersion` is `17 + GITHUB_RUN_NUMBER`, so the first automated build follows the existing build 17.

After completion, verify:

```bash
gh run list --workflow release-direct.yml --repo kargnas/modern-mac-fan-control
gh release view v1.8.3 --repo kargnas/modern-mac-fan-control
```

The repository is currently private, so its release page is also private and returns 404 to signed-out users. Make the repository or a separate download destination public before advertising the download URL.

## Local packaging check

The packager never installs, launches, registers, or unregisters the app/helper. It only writes to `dist-release/`:

```bash
VERSION=1.8.3 \
BUILD_NUMBER=18 \
SIGNING_IDENTITY="Developer ID Application: Example Name (TEAMID)" \
./script/package_release.sh
```

Apple notarization and GitHub Release creation remain workflow responsibilities.
