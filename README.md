[中文版](./README.zh-Hans.md)

# ArcanaCHM

A local-first macOS CHM reader. Native SwiftUI, offline by design.

## Features

- Three-pane SwiftUI layout with WebKit reading surface.
- Import `.chm` files directly — extractor (`7zz`) is bundled inside the app, no Homebrew needed.
- Import already-extracted folders.
- Reading memory per document: last page + scroll position (500ms debounced).
- Bookmarks, search history, full-text search.
- Bilingual UI: English / 中文 (system language by default, manual switch in toolbar).
- Light & dark reading themes, font scaling, focus mode.
- Automatic backup of `library.json` — corrupt files are restored from backup.
- Path sandboxing — no access outside the app's own data directory.
- 90 unit tests covering security policy, TOC parsing, library persistence, CHM importer, encoding, models.

## Requirements

- macOS 14+

## Build

```bash
swift build                       # build executable
Scripts/package_app.sh            # create dist/ArcanaCHM.app
Scripts/package_dmg.sh 1.0.15      # create distributable DMG
```

The app is ad-hoc signed during packaging to prevent macOS's misleading "damaged" alert.

## Use

- `⌘O`: import a CHM file.
- `⇧⌘O`: import an extracted folder.
- Directory tab: document navigation.
- Search tab: full-text local search.
- Favorites tab: bookmarks.

## License

MIT
