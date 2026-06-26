# ArcanaCHM

ArcanaCHM is a local-first macOS CHM reader for general documentation.

## Features

- Native SwiftUI shell with a clean three-pane layout.
- WebKit reading surface with fresh typography, table-friendly styling, font scaling, and focus mode.
- CHM import into a local cache under `~/Library/Application Support/ArcanaCHM`.
- Extracted-folder import for CHM files you have already unpacked.
- Reading memory per document, including last page and scroll position.
- Bookmarks, search history, page-linked favorites, and document-wide local search.
- Light and dark reading themes.
- Offline by design. Rulebook files and notes stay on your Mac.

## Requirements

- macOS 14 or newer.
- Xcode command line tools.
- For direct `.chm` import, install one extractor:

```bash
brew install sevenzip
```

or:

```bash
brew install unar
```

Without an extractor, use **Open Extracted Folder...** after unpacking a CHM yourself.

## Build

From this directory:

```bash
swift build
```

To create a double-clickable app bundle:

```bash
chmod +x Scripts/package_app.sh
Scripts/package_app.sh
```

The app is written to:

```text
dist/ArcanaCHM.app
```

> **Note**: The app is unsigned. On macOS 14+, Gatekeeper may show "ArcanaCHM is damaged and can't be opened" when launching from a downloaded DMG. This is a misleading macOS message for unsigned apps — the app is not actually damaged. To fix, remove the quarantine flag:
>
> ```bash
> xattr -dr com.apple.quarantine /Applications/ArcanaCHM.app
> ```
>
> Or right-click the app in Finder and select **Open** to bypass Gatekeeper once.

## Use

- `Command-O`: import a CHM file.
- `Shift-Command-O`: import an extracted folder.
- Use the directory tab for document navigation.
- Use Search for fast local lookups.
- Use Favorites to revisit saved reading positions.
