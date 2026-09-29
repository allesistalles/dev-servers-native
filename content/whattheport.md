# WhatThePort

> Every dev server on your Mac, in the menu bar. WhatThePort is a free, open-source macOS menu bar app that shows what’s running on localhost: each dev server’s port, project, git branch, uptime, memory and CPU, and the Claude Code, Codex or Conductor session that started it. Stop the ones you forgot about in one click.

- Website and interactive demo: https://whattheport.dev
- Download (Apple Silicon, macOS 14 or later): https://whattheport.dev/WhatThePort.dmg
- Source code (MIT): https://github.com/tomjohndesign/what-the-port
- Guides: https://whattheport.dev/guides
- Price: free. No account.
- Made by Tom John (https://tomjohn.design)

## What it does

- **Every dev server at a glance.** Port, project name, git branch, uptime and memory for each local server, with stable port colors and a whole-Mac memory bar for servers, other apps and free RAM.
- **Knows which agent started it.** Servers launched by Claude Code, Codex or Conductor link back to the session that started them, so you can resume the conversation (`claude --resume`, `codex resume`) or find the Conductor workspace.
- **Leak detection.** When a server passes 2 GB of memory or grows more than 500 MB in ten minutes, its memory reading and the menu bar icon turn amber and you get one notification with Details, Stop and Snooze. Thresholds are adjustable.
- **Resource charts.** Ten minutes of memory and CPU history per server, summed across its whole process tree.
- **Clean up.** Preselects servers from deleted git worktrees or idle for hours, then stops each whole process tree in bulk. Postgres, Redis, MongoDB and MySQL are protected by default. Cleanup can be Off, Ask or Automatic; leaking servers are never stopped automatically.
- **Stop and restart.** Stop sends SIGTERM to the whole process tree, then SIGKILL after a short delay. Restart reruns the original command in the same folder.
- **Previews and pull requests (optional).** A Vercel preview button and the branch’s pull request, through the GitHub CLI you’re already signed in to.
- **Global shortcut.** ⌥⌘P opens the popover.
- **Interface language.** English, German, French, Spanish, Simplified Chinese, Hebrew, Japanese and Ukrainian. Select a language in Settings → General → Language; changes apply immediately. System default follows the Mac’s preferred languages, with English fallback. Hebrew uses right-to-left layout. The site’s Languages section shows the Servers popover demo in each language, using the app’s own translations.
- **Native.** Written in Swift. No Electron, no Dock icon. Light and dark mode.
- **Board.** Overview, All, Local, LAN, Stopped and System. Open, Start, Restart and Kill stay on the card. Known helpers that are not listening show as Stopped: Blackberry web (:8888), Blackberry static (:8899), Blackberry clip (:8900), DialDash (:7878), Droppic (:8787), P1S (:8765), Claude-mem (:37777) and the LED Round Dial companion (:5177). HTTP LaunchAgents in `~/Library/LaunchAgents` join that list. Agents with no port do not become Stopped cards.
- **Controls.** Kill runs `launchctl bootout gui/<uid>/<label>`, then SIGTERM, then SIGKILL, then `/bin/kill -9` if the port is still listening. Start runs `launchctl bootstrap gui/<uid> <plist>` and `launchctl kickstart -k gui/<uid>/<label>`, or the helper’s start command when there is no agent. Open uses the card URL. Firmware-only ports 3232 and 6053 have no Open button.
- **Needs attention.** Stopped helpers and firmware-only devices whose companion is not running.
- **On the network.** Browse `_http._tcp`, `_https._tcp`, `_esphomelib._tcp`, `_arduino._tcp`, `_home-assistant._tcp`, `_hap._tcp` and `_workstation._tcp`. Every `_http`, `_arduino` and `_esphomelib` host is resolved to IPv4 and probed on its advertised port and on port 80. Any HTTP response, including 401, 403 and 404, is a portal with Open. No HTTP response is firmware-only, one card per host. If browse fails, seed hosts are still probed. `_hap` is skipped.
- **Noise.** Claude and OpenCode forwarders, and the P1S mdns and menubar sidecars, are named by role and left out of Stopped and Needs attention. Spotify and rapportd collapse to one system row per process.

The menu-bar app in this fork is **Dev Servers** (bundle id `website.vibed.devservers`). It is based on WhatThePort by Tomjohn, MIT. Source: https://github.com/allesistalles/dev-servers-native and https://github.com/tomjohndesign/what-the-port.

## Install

1. Download https://whattheport.dev/WhatThePort.dmg and open it.
2. Drag WhatThePort onto the Applications shortcut, then open it from Applications.
3. Start a dev server, then click the dot grid in the menu bar or press ⌥⌘P.

The prebuilt download is for Apple Silicon Macs running macOS 14 Sonoma or later. To build from source you need Swift 5.9 or later: `cd WhatThePort && swift build --product DevServers`.

## How it works

WhatThePort reads listening TCP sockets with `lsof`, then inspects each server’s process tree through `libproc` and `sysctl`: memory footprint, CPU time, working directory, arguments and environment. From the working directory it finds the project manifest (package.json, pyproject.toml, Cargo.toml, go.mod, Gemfile), framework and git branch. Session links come from environment variables that Claude Code and Conductor pass to the commands they run, and from Codex’s session files. It rescans every 2 seconds.

By default it watches ports 3000–65535 and processes that look like dev servers: node, bun, deno, python, uvicorn, gunicorn, ruby, rails, puma, php, java, go, cargo, dotnet, elixir, nginx, postgres, redis, mongod, mysql and more. Both are configurable in Settings → Ports & processes.

Frameworks it recognizes include Next.js, Nuxt, Remix, Astro, SvelteKit, Vite, Expo, Angular, Create React App, Hono, Express, Storybook, Django, FastAPI, Flask, Rails, Rust and Go.

## Privacy

There’s no account and no analytics SDK. Everything the app shows comes from your Mac and stays there. It only goes online, if you turn them on, to look up Vercel previews and pull requests through the GitHub CLI.

## FAQ

### Is WhatThePort free?

Yes. It’s free and open source under the MIT license, with no account and no paid tier. There’s an optional tip jar.

### Does it work on Intel Macs or older macOS?

The prebuilt download is for Apple Silicon Macs on macOS 14 Sonoma or later. You can build it from source with Swift 5.9 or later.

### How is it different from `lsof` or `npx kill-port`?

Those answer one question about one port. WhatThePort keeps every dev server in view all the time, names them by project and branch, shows memory and CPU for the whole process tree, warns you about leaks, links servers to the agent session that started them, and stops the whole tree, not just one PID.

### Will it stop my database?

Not unless you choose to. Postgres, Redis, MongoDB and MySQL are protected from Clean up by default, and you can edit the protected list.

### Can a coding agent use it?

Yes. The popover and the detail view show each server’s port, folder, branch, status and the session that started it, so you can reuse a running server instead of starting a duplicate on the next port.

### Where is the menu bar icon?

It’s a small 5×5 dot grid showing a colon. If the menu bar is full, macOS hides icons that don’t fit: click » at its edge on macOS 27, or check System Settings → Menu Bar. Opening WhatThePort again from Finder or Spotlight shows the popover.
