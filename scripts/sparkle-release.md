# Sparkle in-app updates (optional)

TinyAgenda embeds [Sparkle](https://sparkle-project.org/). Updates are **off** until you configure a feed URL and EdDSA public key, then rebuild `TinyAgenda.app`.

## 1. Generate keys (once per app)

Download a Sparkle release (or use Homebrew’s Sparkle cask) and run **`generate_keys`** from the `bin` folder. It prints:

- A **private** key — store only in **GitHub Actions secret** `SPARKLE_EDDSA_PRIVATE_KEY` (entire file contents, including headers if any).
- A **public** key — put into [`Support/Info.plist`](../Support/Info.plist) as **`SUPublicEDKey`** (single line, base64).

Never commit the private key.

## 2. Appcast URL

Set **`SUFeedURL`** in `Support/Info.plist` to an **HTTPS** URL that serves your `appcast.xml`, for example:

`https://raw.githubusercontent.com/<you>/tiny-agenda/main/appcast.xml`

Commit `appcast.xml` to the repo (or host it elsewhere). After each release, add a new `<item>` with the version, download URL to the release zip, and Sparkle signature (from `sign_update` output or the `sparkle-signature-v*.txt` artifact on the GitHub Release).

See Sparkle’s [Publishing an update](https://sparkle-project.org/documentation/publishing/) and `generate_appcast` in the Sparkle distribution for automation.

## 3. GitHub Actions

Workflow [`.github/workflows/release.yml`](../.github/workflows/release.yml) runs on tags `v*`:

- Builds and zips **`TinyAgenda.app`**.
- **Optional** `MACOS_CODESIGN_IDENTITY` — Developer ID signing (paid Apple Developer Program).
- **Optional** `SPARKLE_EDDSA_PRIVATE_KEY` — signs the zip for Sparkle (`sign_update`).

Without Apple secrets, you still get a release zip; Gatekeeper may prompt users until they allow the app. Without Sparkle secrets, skip EdDSA signing and update `appcast.xml` manually if you use Sparkle later.

## 4. Version numbers

Bump **`CFBundleShortVersionString`** and **`CFBundleVersion`** in `Support/Info.plist` for each release so Sparkle can compare versions.
