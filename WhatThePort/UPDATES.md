# Release setup

Dev Servers does not check for updates. Sparkle, the update feed, and anonymous usage sharing are not part of this fork. Install a new build by downloading `WhatThePort.dmg` again.

`./release.sh` still stamps the version, builds `Dev Servers.app`, notarizes it when notary credentials are set, and writes `.build/WhatThePort.dmg`.

## Notarize a local release

From `WhatThePort/`:

```bash
cp update-config.env.example update-config.env
```

Set `CODE_SIGN_IDENTITY` to your Developer ID Application identity and `NOTARYTOOL_PROFILE` to a profile stored with `xcrun notarytool store-credentials`. Or set `NOTARY_API_KEY_PATH`, `NOTARY_API_KEY_ID` and `NOTARY_API_ISSUER_ID` for an App Store Connect API key. Without these, the script ad-hoc signs. Notarization needs Xcode's tools.

Use a new, increasing build number every time:

```bash
./release.sh 2.5 9
```

The script writes `.build/WhatThePort.dmg`. The app inside is `Dev Servers.app`. The disk image filename stays `WhatThePort.dmg` because that is the website download. Do not commit `public/WhatThePort.dmg` or `public/updates/`. The deploy workflow builds the image.

## Release from GitHub Actions

[Rebuild and deploy site and app](../.github/workflows/deploy.yml) builds the app on every push to `main`. It ad-hoc signs until every secret below exists, then switches to Developer ID signing and notarization. If only some are set, the workflow stops.

The version comes from `Info.plist`. Increase `CFBundleVersion` (and usually `CFBundleShortVersionString`) when you want the download to be a new build.

### One-time setup once the Apple Developer membership is active

1. **Developer ID certificate.** Export a **Developer ID Application** certificate and its private key as a `.p12`.
2. **Notary API key.** In App Store Connect, create a team key with the **Developer** role. Download the `.p8` once and note its Key ID and the Issuer ID.
3. **GitHub.** Under Settings → Secrets and variables → Actions, add:

| Name | Kind | Value |
| --- | --- | --- |
| `DEVELOPER_ID_P12` | Secret | `base64 -i DeveloperID.p12` |
| `DEVELOPER_ID_P12_PASSWORD` | Secret | The export password |
| `NOTARY_API_KEY` | Secret | Contents of the `.p8` file |
| `NOTARY_API_KEY_ID` | Secret | The key's ID |
| `NOTARY_API_ISSUER_ID` | Secret | Your team's issuer ID |

Then run **Actions → Rebuild and deploy site and app → Run workflow** on `main`.

## Download analytics

Download buttons on the site send a **Download** Web Analytics event with a `location` (`hero`, `get-it` or `footer`). The site still answers `/usage/<feature>` with an empty 204 so older WhatThePort builds do not see an error. This fork does not send those requests.

## Verify a release

```bash
python3 scripts/test-configure-updates.py
codesign --verify --deep --strict ".build/Dev Servers.app"
```
