# Interface translations

WhatThePort supports English (`en`), German (`de`), French (`fr`), Spanish (`es`), Simplified Chinese (`zh-Hans`), Hebrew (`he`), Japanese (`ja`) and Ukrainian (`uk`). Select a language in **Settings → General → Language**. Changes apply immediately. Switching languages rebuilds the displayed views; scanning and running servers retain their state.

**System default** walks the Mac’s preferred languages in order and selects the first supported language, falling back to English. Traditional Chinese is not silently substituted with Simplified Chinese. Hebrew uses right-to-left SwiftUI layout. Fonts fall back to macOS fonts for scripts not covered by Geist.

## Adding or correcting a translation

Each language has a complete `Sources/WhatThePort/Resources/<code>.lproj/Localizable.strings` table inside `WhatThePort/`. English phrases are the keys and fallback values. Keep brand names and command examples unchanged. Preserve every format argument’s type and position. When rearranging arguments, number **all** arguments explicitly (for example `%2$@` before `%1$@`). Avoid constructing sentences by joining independently translated fragments.

Register new languages in `InterfaceLanguage` and `app/components/languages.ts`. Add it to `LANGUAGES` in `scripts/app-strings.mjs` and run `node scripts/app-strings.mjs`, then update marketing copy and the language guide. `swift build --product DevServers` processes the resources and `./build-app.sh` embeds the resource bundle in the app. The resolver uses the bundle’s declared localization spelling, including SwiftPM’s normalized `zh-hans` directory.

The initial Simplified Chinese translation and resource architecture come from [PR #32](https://github.com/tomjohndesign/what-the-port/pull/32). The additional translations are an initial pass; fluent-speaker review is welcome, especially for longer explanatory copy and grammar around counts. Portuguese, Korean and Traditional Chinese are useful candidates for a later expansion, with their own complete resource tables and review.

## Verification

From `WhatThePort/` on a Mac, run `swift test`. Localization tests load all eight bundled tables, check exact key coverage and placeholder positions, and test language preference fallback. On Linux, `swift test --filter DevServersCoreTests` runs the board tests only. The app target is omitted there.

`swift run DevServers --snapshot <dir> --ui-language he` captures the popover. It does not change macOS permissions.

The website’s Languages section shows its interactive Servers popover in whichever language the rotating headline is showing, using the app’s own translations. `scripts/app-strings.mjs` copies the phrases the popover needs from `Localizable.strings` into `app/components/appStrings.json`; builds fail if that file is stale. The other website demos remain English.

On Command Line Tools installations where Swift Testing is outside the default search path, use:

```sh
swift test --jobs 4 \
  -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```
