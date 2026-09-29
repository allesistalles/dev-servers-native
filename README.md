# Dev Servers

Native macOS menu-bar app for local dev servers, LaunchAgents and LAN devices. This is a fork of [WhatThePort](https://github.com/tomjohndesign/what-the-port) by Tom Johnson, MIT. The popover is the Dev Servers board: helpers, listeners, and LAN devices, with Open, Start, Restart and Kill.

The app’s display name is **Dev Servers**. Bundle id: `website.vibed.devservers`. The website download stays [`/WhatThePort.dmg`](https://whattheport.dev/WhatThePort.dmg).

**Every dev server on your Mac, in the menu bar.**

What it is, what branch it’s on, which agent started it, and what it’s costing you. Stop the ones you forgot about in one click.

[**Download for macOS**](https://whattheport.dev/WhatThePort.dmg) · [Try the interactive demo](https://whattheport.dev) · [Guides](https://whattheport.dev/guides) · [Build from source](#building)

Free and open source · macOS 14 or later · No account

[![WhatThePort marketing demo showing the server list, ports, branches, memory use, and CPU in a Mac menu bar popover](docs/images/servers.jpg)](https://whattheport.dev)

## Know what’s running

WhatThePort is a native Swift app that lives in your menu bar, with no Dock icon. Press **⌥⌘P** to see your local development servers: project names, ports, git branches, uptime, and resource use. Open a server in your browser, inspect its processes, or stop and restart it without hunting through terminals.

### Knows which agent started it

Servers launched by Claude Code, Codex, or Conductor link back to the session that started them. Pick up the conversation, check the branch, or open a Vercel preview. Optional pull request links use the GitHub CLI you’re already signed in to.

![Marketing demo of a server’s detail view with its agent session, git branch, memory and CPU charts, and preview link](docs/images/sessions.jpg)

### Notices before your fans do

When a server passes the default 2 GB memory threshold or grows more than 500 MB in ten minutes, WhatThePort turns its menu bar amber and sends a notification. Port colors stay consistent, while amber memory readings flag servers needing attention. Ten minutes of memory and CPU history show what’s happening across the whole process tree. Adjust thresholds and snooze alerts in Settings.

![Marketing demo showing a rising memory chart and the amber alert threshold for a development server](docs/images/leaks.jpg)

### Stops the ones you forgot

**Clean up** adds checkboxes to the server list and preselects servers from deleted worktrees or idle for hours. Tick the ones to go and WhatThePort stops each whole process tree. Database processes such as Postgres and Redis are protected by default.

Choose **Off**, **Ask**, or **Automatic** cleanup in Settings. Leaking servers are never stopped automatically.

![Marketing demo of Clean up with idle and deleted-worktree servers selected for removal](docs/images/clean-up.jpg)

*Screenshots from the [marketing site’s interactive demo](https://whattheport.dev), using sample server data.*

## Get started

1. [Download WhatThePort](https://whattheport.dev/WhatThePort.dmg) and open it.
2. Drag **WhatThePort** onto the **Applications** shortcut beside it, then open it from Applications.
3. Start a development server, then click the dot grid in your menu bar or press **⌥⌘P**.

The prebuilt download is for **Apple Silicon Macs running macOS 14 or later**. To compile the app yourself, you’ll also need **Swift 5.9+**.

## Features

- **Board** - Overview, All, Local, LAN, Stopped and System. The popover is that board: Mac helpers, dev servers and listeners, and LAN devices
- **Open, Start, Restart and Kill** - On each card you can control. Any HTTP response, including 404, is a portal with Open. No HTTP response is one OTA card per host
- **LAN** - mDNS hosts on `_http`, `_arduino` and `_esphomelib`, probed on the advertised port and port 80. Seed hosts are still probed if browse returns nothing
- **Global shortcut** - ⌥⌘P opens the popover
- **Light and dark mode** - Follows your Mac’s appearance, with matching port numbers and colon colors

## Usage

Dev Servers lives in the menu bar as a small dot grid. Click it to see the board:

- Open, Start, Restart and Kill sit on each card you can control
- LAN cards with a web portal have Open. Firmware-only cards do not

Right-click the dot grid to open a server in the browser, open Settings, send feedback or quit.

Can't see the dot grid? The menu bar hides icons that don't fit: click » at its edge on macOS 27, or check **System Settings → Menu Bar**. Opening WhatThePort again from Finder or Spotlight shows the popover, or Settings when the icon is hidden.

To check the UI without the menu bar, `swift run DevServers --snapshot <dir>` renders each view with live data to PNG.
Add `--appearance light` or `--appearance dark` to check a specific appearance without changing your Mac’s settings.

### Interface language

The native app supports **English, German, French, Spanish, Simplified Chinese, Hebrew, Japanese and Ukrainian**. Choose your language in **Settings → General → Language**. Changes apply immediately. System default follows your Mac’s preferred languages, falling back to English. Hebrew uses a right-to-left layout.

[Preview all eight languages](https://whattheport.dev/#translations) or read [Localization](LOCALIZATION.md) for translation and build details.

### Settings

Open Settings from the gear in the popover (⌘,):

- **General** - Language, launch at login, menu bar icon style, global shortcut, scan interval
- **About** - Version, bug reports or feature requests as GitHub issues, a tip jar, and credit as a fork of WhatThePort by Tom Johnson

## How It Works

Dev Servers reads listening TCP sockets with `lsof`, then names local listeners from the project folder. It also browses mDNS and probes each host on its advertised port and port 80. It rescans every 2 seconds.

## Privacy

There's no account, no analytics SDK, and no usage sharing. Everything the app shows comes from your Mac and stays there. The app does not check for updates.

The website uses cookieless [Vercel Web Analytics](https://vercel.com/docs/analytics) to count visits and download clicks.

## Build and install on a Mac

This VM cannot compile the AppKit/SwiftUI app. The package is Swift 5.9 language mode. It builds with Apple Swift 6.4 and the Command Line Tools, without Xcode, against the macOS 26.5 SDK. From the repo root:

```bash
cd WhatThePort
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
swift build -c release
./build-app.sh
cp -R ".build/Dev Servers.app" /Applications/
codesign --force --deep --sign - "/Applications/Dev Servers.app"
open "/Applications/Dev Servers.app"
```

Export `SDKROOT` in the same shell before `./build-app.sh`. That script runs `swift build -c release --product DevServers` again, and it inherits the variable. The package has no Sparkle or FlickerDot dependency. Onboarding was the only FlickerDot user, and it is gone, so the macOS 27 Command Line Tools failure on FlickerDot `@State` (missing SwiftUIMacros without Xcode) no longer applies. `SDKROOT` can stay on the 26.5 SDK.

`./build-app.sh` already ad-hoc signs the bundle (`codesign --sign -`). The copy into `/Applications` needs a second ad-hoc signature because copying can break the seal. The executable inside the bundle is `DevServers`. Finder and the menu bar show **Dev Servers**. The app bundle is still `Dev Servers.app`.

The same build with Xcode:

```bash
cd WhatThePort
unset SDKROOT
xcodebuild -scheme DevServers -destination 'platform=macOS' -configuration Release build
./build-app.sh
cp -R ".build/Dev Servers.app" /Applications/
codesign --force --deep --sign - "/Applications/Dev Servers.app"
```

`./build-app.sh` is what produces `Dev Servers.app` with the resources in the right places. If you already exported `SDKROOT` for the Command Line Tools, unset it before `xcodebuild`. Quit any old copy first: this fork’s bundle id is `website.vibed.devservers`, so macOS treats it as a different app.

Check the classification logic without a Mac (Linux or Mac):

```bash
cd WhatThePort
swift test --filter DevServersCoreTests
```

`Package.resolved` has no pins. Sparkle and FlickerDot are not dependencies.

### What could not be compiled here

This environment is Linux. `swift test --filter DevServersCoreTests` builds and runs `DevServersCore` only. The menu-bar target does not build here, so these files were not type-checked by a compiler:

- `WhatThePort/Sources/WhatThePort/` (SwiftUI and AppKit), including `BoardDiscovery.swift`, `BoardActions.swift`, `BonjourBrowser.swift`, `LaunchAgentController.swift`, `ServiceSections.swift`, and the `ServerMonitor` wiring
- `dns-sd`, `launchctl`, `NSWorkspace`, and the popover layout

`Package.swift` omits that target on Linux so the core tests can run. On a Mac the whole package builds.

### Behavior notes

The Electron repo was not readable from the build environment. The rules below follow the pasted `companions.js`, `hosts.js`, `mdns.js`, `probe.js`, `board.js`, `control.js`, `launch-agents.js`, `actions.js` and `known-helpers.js` excerpts, and `DevServersCoreTests` covers the pure parts.

- Known helpers are the curated list: Blackberry web, static and clip as three cards, DialDash, Droppic, Translator, P1S, Claude-mem and LED Round Dial. Port 5177 is the dial even when the process is Vite. HTTP LaunchAgents that are not on that list are added beside it. Agents with no port are not Stopped cards. Sidecars (Claude/OpenCode forwarders, P1S mdns, P1S menubar) show only while running.
- Spotify and `rapportd` become one system row per process name. Those rows are not stoppable.
- Kill runs `launchctl bootout gui/<uid>/<label>`, then SIGTERM, then SIGKILL, then `/bin/kill -9`. Start runs `launchctl bootstrap` and `kickstart -k`, or the helper’s start command when there is no agent. Open uses the card URL. Firmware-only ports 3232 and 6053 have no Open button.
- There is no `wtp` command and no in-app updater.

Signing and notarization for a local release are in [Release setup](WhatThePort/UPDATES.md). The release script packages a notarized disk image. It does not publish an update feed.

To package a local build as the download's disk image, run `./make-dmg.sh` after `./build-app.sh`. The disk image file stays `WhatThePort.dmg` so the site link does not change. The volume name and the app inside it are Dev Servers.

## Automatic deployment

Every push to `main`, including a merged pull request, runs
[Rebuild and deploy site and app](.github/workflows/deploy.yml). It builds the
Apple Silicon Mac app on macOS, verifies its ad-hoc signature, and packages it as
`WhatThePort.dmg` ([`make-dmg.sh`](WhatThePort/make-dmg.sh)): the app beside an
Applications shortcut, on a background designed in Paper
([`WhatThePort/dmg/`](WhatThePort/dmg)). A Linux job then puts that artifact at `public/WhatThePort.dmg`,
builds the Next.js site, and deploys both together to production on Vercel. A
failed app or site build stops deployment.

The download is never checked in, so the site always serves the latest release.
Production builds fail unless `public/WhatThePort.dmg` is a disk image and any
update feed is for this commit's build ([`scripts/check-download.mjs`](scripts/check-download.mjs)). Local dev
and preview deployments don't have the file, so they redirect downloads to
production.

Configure these GitHub Actions **repository secrets** under
**Settings → Secrets and variables → Actions** before merging this workflow:

- `VERCEL_TOKEN`: a Vercel access token with access to the production project.
- `VERCEL_ORG_ID`: the production project's `orgId` from `.vercel/project.json`.
- `VERCEL_PROJECT_ID`: its `projectId` from `.vercel/project.json`.

Run `vercel link` locally to obtain the project IDs. Keep tokens and the generated
`.vercel` directory out of Git.

The app's tip jar opens `whattheport.dev/tip`, which redirects to the `TIP_URL`
environment variable, so the payment page can change without an app update. Create
a Stripe [Payment Link](https://dashboard.stripe.com/payment-links) and set its
type to **Customers choose what to pay** (not a product price), then add it to the Vercel project's production
environment with `vercel env add TIP_URL production`. Production builds fail
without it ([`scripts/check-tip.mjs`](scripts/check-tip.mjs)); local dev and
previews redirect `/tip` to production.

`vercel.json` disables Vercel's automatic Git deployments for `main`, so only this
workflow publishes production with the freshly built app. Other branches retain
Vercel's normal preview deployments. To retry production,
use **Actions → Rebuild and deploy site and app → Run workflow** with `main`
selected. Production runs are serialized; GitHub may replace a pending run with
a newer one when several merges arrive during an active deployment.

Until its signing secrets are configured, the workflow uses ad-hoc signing.
Once they are, it signs with Developer ID and notarizes the app. There is no
Sparkle feed. See [Release from GitHub Actions](WhatThePort/UPDATES.md#release-from-github-actions).

## About

Dev Servers is based on [WhatThePort](https://github.com/tomjohndesign/what-the-port) by [Tomjohn](https://tomjohn.design), MIT. This fork is [allesistalles/dev-servers-native](https://github.com/allesistalles/dev-servers-native). Explore the [interactive demo](https://whattheport.dev), read the [guides](https://whattheport.dev/guides), or browse the source. Agents can read the site as Markdown from [`/llms.txt`](https://whattheport.dev/llms.txt). If the app saves you time, [buy Tomjohn a coffee](https://whattheport.dev/tip).

## License

[MIT](LICENSE)
