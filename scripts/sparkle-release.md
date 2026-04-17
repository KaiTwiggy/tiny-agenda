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

Use your **default branch** name in the path if it is not `main`.

Commit a baseline **`appcast.xml`** at the repo root (channel metadata only is fine). **After each tagged release**, if the repository secret **`SPARKLE_EDDSA_PRIVATE_KEY`** is set, the [Release workflow](../.github/workflows/release.yml) runs **`scripts/update-appcast.py`**, which **replaces** the feed with **one** `<item>` for the latest release only (zip URL, length, `sparkle:edSignature`), commits to the default branch, and pushes.

Sparkle can read feeds with multiple items, but this project intentionally ships a **single latest entry** so the raw URL always matches one version. Without the secret, maintain that one `<item>` yourself using `sign_update` or the `sparkle-signature-v*.txt` artifact.

See Sparkle’s [Publishing an update](https://sparkle-project.org/documentation/publishing/) and `generate_appcast` in the Sparkle distribution for more options.

## 3. GitHub Actions

Workflow [`.github/workflows/release.yml`](../.github/workflows/release.yml) runs on tags `v*`:

- Builds and zips **`TinyAgenda.app`**.
- **Optional** `MACOS_CODESIGN_IDENTITY` — Developer ID signing (paid Apple Developer Program).
- **Optional** `SPARKLE_EDDSA_PRIVATE_KEY` — signs the zip for Sparkle (`sign_update`) and **updates/commits `appcast.xml`** on the default branch.

Without Apple secrets, you still get a release zip; Gatekeeper may prompt users until they allow the app. Without `SPARKLE_EDDSA_PRIVATE_KEY`, there is no EdDSA signature and **no automatic appcast commit** — add appcast items manually or skip Sparkle updates.

## 4. Version numbers

**GitHub Actions (tag builds):** the Release workflow **overwrites** `Support/Info.plist` **`CFBundleShortVersionString`** and **`CFBundleVersion`** from the tag (`v1.0.5` → `1.0.5` for both). Use tags like **`vMAJOR.MINOR.PATCH`** so the built app and Sparkle appcast stay aligned.

**Local builds:** bump **`CFBundleShortVersionString`** and **`CFBundleVersion`** in `Support/Info.plist` yourself, or match what you will tag.
