---
title: Change WhatThePort’s app language
description: Choose English, German, French, Spanish, Simplified Chinese, Hebrew, Japanese or Ukrainian during setup, in Settings, or from the terminal.
published: 2026-09-28
updated: 2026-09-28
order: 10
keywords: WhatThePort language, translations, Japanese, Ukrainian, German, French, Chinese, Hebrew, Spanish, macOS language
---

WhatThePort’s native Mac interface is available in eight languages:

| Language | Name in the picker | Code |
| --- | --- | --- |
| English | English | `en` |
| German | Deutsch | `de` |
| French | Français | `fr` |
| Spanish | Español | `es` |
| Simplified Chinese | 简体中文 | `zh-Hans` |
| Hebrew | עברית | `he` |
| Japanese | 日本語 | `ja` |
| Ukrainian | Українська | `uk` |

## Choose during setup or later

On the first onboarding screen, use the **Language** picker. The interface changes immediately, and a preview beneath the picker shows two sample server rows as they’ll appear in the menu bar, so you can continue setup in that language. Later, open **Settings → General → Language** to change it again.

**System default** uses the first supported language in your Mac’s preferred language list, with English as the fallback. Traditional Chinese is not treated as Simplified Chinese. Hebrew uses a right-to-left layout.

## Set the app language from the terminal

Once the `wtp` command is installed through onboarding or **Settings → General → Terminal**, show the current preference:

```sh
wtp language
```

For example, switch the app to Japanese:

```sh
wtp language ja
```

Or return to your Mac’s preferred language:

```sh
wtp language system
```

Use any code from the table above. The terminal’s **?** help screen also shows the app language.

## What changes, and what stays the same

Labels, settings, onboarding, menus, alerts and accessibility copy are translated. Project names, branches, paths, commands and session identifiers remain exactly as they are. Changing language does not stop or restart your development servers.

The `wtp` terminal interface stays in English, including command help and JSON field names. The website is also in English; its [Languages section](/#translations) shows the Servers popover demo in each language, using the app’s own translations.

The translations are open source. If a phrase could be clearer, [suggest a correction on GitHub](https://github.com/tomjohndesign/what-the-port). See [the localization notes](https://github.com/tomjohndesign/what-the-port/blob/main/LOCALIZATION.md) for resource files and testing details.

[Download WhatThePort for macOS](/WhatThePort.dmg).
