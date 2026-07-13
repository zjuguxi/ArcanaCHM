[中文版](./README.zh-Hans.md)

# ArcanaCHM

A local-first macOS CHM reader. Native SwiftUI, offline by design.

**Website:** https://zjuguxi.github.io/ArcanaCHM/

## Features

- Three-pane SwiftUI layout with WebKit reading surface.
- Import `.chm` files directly — extractor (`7zz`) is bundled inside the app, no Homebrew needed.
- Import already-extracted folders.
- Reading memory per document: last page + scroll position (500ms debounced).
- Bookmarks, search history, full-text search.
- Find in page (Cmd+F) with match navigation.
- Bilingual UI: English / 中文 (system language by default, manual switch in toolbar).
- Light & dark reading themes, font scaling, focus mode.
- Automatic backup of `library.json` — corrupt files are restored from backup.
- Path sandboxing — no access outside the app's own data directory.
- 176 unit and performance tests covering security policy, TOC parsing, isolated library persistence, bounded CHM import, encoding, and models.

## Requirements

- macOS 14+

## Build

```bash
swift build                       # build executable
Scripts/package_app.sh 1.3.5      # create an ad-hoc signed local app
Scripts/package_dmg.sh 1.3.5      # create distributable DMG
```

Local packages are ad-hoc signed. Tagged releases require Developer ID signing, Hardened Runtime, notarization, and stapling in GitHub Actions. The bundled 7-Zip archive and binary are verified against pinned SHA-256 values.

Imported archives are subject to file-count, size, depth, disk-space, and time limits. App data paths are dependency-injected so tests only use uniquely named temporary directories and never the production library.

## Use

- `⌘O`: import a CHM file.
- `⇧⌘O`: import an extracted folder.
- Directory tab: document navigation.
- Search tab: full-text local search.
- Favorites tab: bookmarks.

## License

MIT
