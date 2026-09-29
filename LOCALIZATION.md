# Interface translations

WhatThePort supports English (`en`), German (`de`), French (`fr`), Spanish (`es`), Simplified Chinese (`zh-Hans`), Hebrew (`he`), Japanese (`ja`) and Ukrainian (`uk`). Select a language on the first onboarding screen or in **Settings → General → Language**. Changes apply immediately. Switching languages rebuilds the displayed views; scanning and running servers retain their state.

**System default** walks the Mac’s preferred languages in order and selects the first supported language, falling back to English. Traditional Chinese is not silently substituted with Simplified Chinese. Hebrew uses right-to-left SwiftUI layout. Fonts fall back to macOS fonts for scripts not covered by Geist.

## Terminal

The TUI and machine-readable output remain English. `wtp language` reads the shared **app** language; `wtp language de` sets it, and `wtp language system` restores automatic selection. The TUI’s `?` screen displays App language. Commands, JSON keys, project names, paths, branches, ports and session identifiers retain their original values. Terminal rendering of Hebrew project names depends on the terminal’s bidirectional-text support; this is not a translated Hebrew TUI.

## Adding or correcting a translation

Each language has a complete `Sources/WhatThePort/Resources/<code>.lproj/Localizable.strings` table inside `WhatThePort/`. English phrases are the keys and fallback values. Keep brand names and command examples unchanged. Preserve every format argument’s type and position. When rearranging arguments, number **all** arguments explicitly (for example `%2$@` before `%1$@`). Avoid constructing sentences by joining independently translated fragments.

Register new languages in `InterfaceLanguage`, the terminal’s help and validation message, and `app/components/languages.ts`. Add a real onboarding screenshot to `public/languages/`, update marketing copy and the language guide. `swift build` processes the resources and `./build-app.sh` embeds the resource bundle in the app. The resolver uses the bundle’s declared localization spelling, including SwiftPM’s normalized `zh-hans` directory.

The initial Simplified Chinese translation and resource architecture come from [PR #32](https://github.com/tomjohndesign/what-the-port/pull/32). The additional translations are an initial pass; fluent-speaker review is welcome, especially for longer explanatory copy and grammar around counts. Portuguese, Korean and Traditional Chinese are useful candidates for a later expansion, with their own complete resource tables and review.

## Verification

From `WhatThePort/`, run `swift test`. Tests load all eight bundled tables, check exact key coverage and placeholder positions, test language preference fallback, and exercise terminal input and column widths for Latin, Hebrew, CJK and Cyrillic text.

`WhatThePort --snapshot-onboarding <dir> --ui-language ja --appearance dark` renders the welcome screen plus deterministic loading, permission and success states without persisting preferences or changing macOS permissions. `--snapshot <dir> --ui-language he` also captures server details, cleanup and every settings pane. The site’s language selector previews these native screenshots; the existing interactive server and terminal demos remain English.

On Command Line Tools installations where Swift Testing is outside the default search path, use:

```sh
swift test --jobs 4 \
  -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```
