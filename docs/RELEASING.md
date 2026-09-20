# Releasing

A release is cut by pushing a tag. The workflow in
[`.github/workflows/release.yml`](../.github/workflows/release.yml) builds,
signs, notarises and staples the app, then attaches it to a GitHub release
along with the `mdv` command line tool and a checksum file.

```bash
git tag v0.2.0
git push origin v0.2.0
```

The tag is the version: `v0.2.0` builds a bundle that reports `0.2.0`. Nothing
in the repository records the version, so there is no second place to forget.

## Secrets

The workflow reads everything sensitive from **GitHub encrypted secrets**. Set
them under **Settings ▸ Secrets and variables ▸ Actions ▸ New repository
secret**. GitHub encrypts them at rest, masks them in logs, and never exposes
them to a workflow run from a fork.

Nothing below should ever be committed, pasted into an issue, or held anywhere
but that settings page.

### Signing — required

| Secret | What it is |
|---|---|
| `DEVELOPER_ID_P12` | Your **Developer ID Application** certificate and private key, as a base64 `.p12` |
| `DEVELOPER_ID_P12_PASSWORD` | The password you set when exporting that `.p12` |
| `APPLE_TEAM_ID` | Your ten-character team identifier |

To export the certificate: open **Keychain Access**, find *Developer ID
Application: …*, expand it so both the certificate and its private key are
selected, right-click ▸ **Export 2 items…**, save as `.p12` with a password.
Then:

```bash
base64 -i DeveloperID.p12 | pbcopy      # paste as DEVELOPER_ID_P12
```

Your team identifier is in the Apple Developer portal under **Membership**, and
is also the string in parentheses after your name in the certificate.

### Notarisation — one of the two sets below

An **App Store Connect API key** is the better choice for CI. It is scoped to
what it may do, can be revoked on its own, and is not tied to one person's
two-factor login, so it does not break when someone changes their Apple ID
password.

| Secret | What it is |
|---|---|
| `APPSTORE_API_KEY_P8` | The `.p8` private key, base64 encoded |
| `APPSTORE_API_KEY_ID` | The key's ten-character identifier |
| `APPSTORE_API_ISSUER_ID` | The issuer UUID shown above the key list |

Create one at [App Store Connect ▸ Users and Access ▸
Integrations ▸ App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api),
with the **Developer** role. The `.p8` can be downloaded exactly once, so save
it before closing the page. Then:

```bash
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy    # paste as APPSTORE_API_KEY_P8
```

Failing that, an Apple ID with an app-specific password also works:

| Secret | What it is |
|---|---|
| `APPLE_ID` | The Apple ID of your developer account |
| `APPLE_APP_PASSWORD` | An app-specific password from [appleid.apple.com](https://appleid.apple.com) ▸ Sign-In and Security |
| `APPLE_TEAM_ID` | As above |

The workflow prefers the API key and falls back to the password. If neither is
set it stops before notarising and says which secrets are missing, rather than
publishing a build that Gatekeeper will refuse.

## What the workflow checks

Two things are asserted rather than assumed, because both fail silently:

- **The extension keeps its sandbox entitlement.** PlugInKit refuses to register
  a Quick Look extension whose entitlements were stripped after signing, and
  says so only in `pkd`'s log. The build fails instead of shipping a dead
  preview.
- **Gatekeeper accepts the stapled app.** `spctl --assess` runs after stapling,
  so the verdict in the log is the one a person downloading it will get.

## Running it by hand

The workflow also has a `workflow_dispatch` trigger, so it can be run from the
Actions tab against any branch. Without a tag the version falls back to
`0.0.0-dev` and the release is still created, which is useful for testing the
signing path without minting a version number.
