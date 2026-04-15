# TinyAgenda

Menu bar app for macOS that shows your next Google Calendar meetings using a **secret iCal (ICS) feed URL**—no Google Cloud project and no OAuth.

This project is [open source](../LICENSE) under the MIT License. See the repository root for [contributing](../CONTRIBUTING.md), [security reporting](../SECURITY.md), and [code of conduct](../CODE_OF_CONDUCT.md).

[![CI](https://github.com/KaiTwiggy/tiny-agenda/actions/workflows/ci.yml/badge.svg)](https://github.com/OWNER/REPO/actions/workflows/ci.yml)

## Requirements

- **macOS 13** or later
- **Xcode** (or a Swift toolchain with the macOS SDK) to build from source

## Setup

1. In [Google Calendar](https://calendar.google.com), open **Settings** for the calendar you want.
2. Under **Integrate calendar**, copy **Secret address in iCal format** (HTTPS URL).
3. Build a proper app bundle and launch it (**recommended**). `swift run` starts a bare binary; on current macOS, **User Notifications crash** without a real `.app` bundle.

```bash
cd tiny-agenda
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open TinyAgenda.app
```

To build without opening the app:

```bash
swift build -c release
swift test
```

Use the `.app` produced by `build-app.sh` for notifications and “Open at login” (see below).

4. Open **Settings** from the menu bar, paste the URL, and click **Save**.

The URL is stored in the **Keychain** on your Mac. **Do not** share it, commit it to git, or paste it into public issues.

## Privacy

- **Calendar data** comes from the ICS feed you configure; it is fetched over the network and kept in memory for display and notification scheduling.
- The **feed URL** is stored in the **Keychain**, not in plain `UserDefaults`.
- This app does **not** include analytics or crash reporting unless you add such code; the stock codebase does not phone home.

Treat ICS content as **untrusted** (display only—no execution of code from the feed). Prefer **HTTPS** feed URLs.

## Features

- **Open at login:** Settings → Startup → “Open at login” (uses the system Login Items API; run from `TinyAgenda.app`).
- Menu bar title: countdown to the next timed event, or the start time if farther out (all-day events are excluded from the title).
- Dropdown: upcoming events, **Open link** when a URL appears in the event text.
- Notifications before events (configurable minutes: 5, 10, 15, 30, 60).
- Optional quiet hours (e.g. 22:00–07:00) to suppress notification scheduling.
- Refresh interval: 60–600 seconds (default 120).

## Releases and distribution

- **From source:** Clone the repo, run `./scripts/build-app.sh`, and open `TinyAgenda.app` locally.
- **GitHub Releases:** Push a tag `v*` (e.g. `v1.0.1`). [`.github/workflows/release.yml`](.github/workflows/release.yml) builds `TinyAgenda.app`, zips it, and attaches **`TinyAgenda-vX.Y.Z.zip`** to a GitHub Release. **No Apple Developer account is required** for that workflow.
- **Optional Developer ID signing:** Set repository secret `MACOS_CODESIGN_IDENTITY` (e.g. `Developer ID Application: Your Name (TEAMID)`) so the release job code-signs the app before zipping. Omit it to ship **ad-hoc** signed builds; Gatekeeper may prompt users until they allow the app.
- **In-app updates (Sparkle):** Optional. Configure `SUFeedURL` / `SUPublicEDKey` in [`Support/Info.plist`](Support/Info.plist) and maintain an `appcast.xml`. See [`scripts/sparkle-release.md`](scripts/sparkle-release.md) and [`appcast.xml.example`](appcast.xml.example). Optional secret `SPARKLE_EDDSA_PRIVATE_KEY` adds a `sign_update` artifact to the release.

## Limits

- ICS feeds can lag a few minutes behind the web calendar.
- Recurring rules are handled in a simplified way; complex recurrence may differ from Google’s UI.

## Naming

This is an independent project and is **not** affiliated with Google LLC or Apple Inc. “Google Calendar” is a trademark of Google.
