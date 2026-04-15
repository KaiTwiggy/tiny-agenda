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
- **GitHub Releases (optional):** Maintainers may attach a built `.zip` or `.app`. Binaries may be **ad-hoc signed** (`build-app.sh`); Gatekeeper may prompt until the user allows the app. **Notarized** builds require a paid Apple Developer Program workflow not included in this repository.
- **Version tags:** Semantic versions (e.g. `v1.0.0`) can tag known-good commits for reproducibility.

## Limits

- ICS feeds can lag a few minutes behind the web calendar.
- Recurring rules are handled in a simplified way; complex recurrence may differ from Google’s UI.

## Naming

This is an independent project and is **not** affiliated with Google LLC or Apple Inc. “Google Calendar” is a trademark of Google.
