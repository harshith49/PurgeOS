# PurgeOS

A free, MIT-licensed, offline native macOS maintenance app. SwiftUI, AppKit, FileManager, CryptoKit, Swift Charts, Mach and IOKit; no third-party dependencies, accounts, ads, subscriptions, telemetry, servers or AI services.

## Build and install

Requires macOS 13+ and Swift 5.9+ (Xcode or Apple Command Line Tools). Install Apple's free tools with `xcode-select --install` if needed. Open `Package.swift` in Xcode, or:

```sh
swift build
swift run SafetyChecks
./scripts/build-app.sh
open dist/$(uname -m)/PurgeOS.app
```

Copy the resulting app to `/Applications` to install. A metadata-free `dist/<architecture>/PurgeOS.zip` is also generated. For synced workspaces that add Finder metadata and invalidate ad-hoc signatures, extract this ZIP outside the synced folder (for example in `/Applications`). The build uses free ad-hoc signing; no Apple developer membership is needed for local use. Downloaded unsigned builds may require approval in System Settings > Privacy & Security. No paid signing or notarization is required to build and run your own copy.

For Intel: `./scripts/build-app.sh x86_64`. For Apple Silicon: `./scripts/build-app.sh arm64`. Both architectures target macOS 13+. Test on the target hardware before distributing. Build inputs are local after installing Apple's toolchain; package resolution downloads nothing.

## Modules

- **Overview:** actual CPU tick deltas, active+wired+compressed RAM, home-volume capacity/free space, battery charge, cycles and design-capacity health when hardware exposes it. Unavailable metrics are labeled. CPU history updates every two seconds.
- **Smart Junk / Cache Cleaner:** regular local files in the current user's `Library/Caches` and (for smart junk) `Library/Logs`, older than seven days. Age is a review heuristic, not a guarantee a file is unused. Quit related apps before cleanup.
- **Duplicates:** size prefilter followed by streaming SHA-256 content hashes. Hard links are excluded within size groups. Nothing is selected automatically; at least one copy must remain in each displayed group.
- **Large Files:** files at least 100 MiB under a chosen folder.
- **Uninstaller:** scans top-level `/Applications` bundles, requires selection and confirmation, refuses running apps. Support data, documents, services and privileged helpers are retained. This is a safe bundle uninstaller, not a privileged removal daemon.
- **Storage:** interactive category bar chart and file table for the selected folder. Logical sizes can differ from APFS physical use because of compression, clones and snapshots. Right-click a row to reveal it in Finder.
- **Downloads:** selects only top-level regular files in your Downloads. Organize moves them into Images, Videos, Audio, Documents, Archives or Other. Existing destinations are never overwritten.
- **Menu bar:** live CPU, memory and battery readings, open and quit actions.
- **History:** atomic local JSON log of successful Trash/organize operations at `~/Library/Application Support/PurgeOS/history.json`.

## Safety and permissions

Every Trash action requires explicit selection and confirmation. PurgeOS never empties Trash or permanently deletes files. Restore through Finder's Trash > Put Back. Organizer changes are recorded with their destinations; move them back in Finder if needed.

No elevated privileges or privileged helpers. System directories, other users, sensitive user Library directories, SSH/GPG keys, Trash and symlinks are rejected by a shared mutation boundary. Only user cache/log contents inside Library are eligible. Top-level `/Applications/*.app` bundles are the sole exception outside your home. Symlink traversal is rejected again immediately before mutation. macOS may still deny access; errors are shown, not silently treated as success. Full Disk Access is optional; choose folders you can read. Cloud-managed files and package descendants are skipped to avoid downloads and app internals during ordinary scans. App bundle sizing explicitly scans bundle contents.

Scans run off the main actor and are cancellable between files. A current hash read must finish before cancellation returns. Results are kept in memory and can be large on very large folders. File actions run serially. Files can change after scanning; review immediately before cleanup. As with any unprivileged path-based filesystem app, concurrent filesystem replacement cannot be fully prevented; don't clean folders being actively modified by other tools. A history-write failure after a move is reported, but cannot undo the move; check Finder before retrying.

## Project structure

```
Package.swift
Sources/PurgeCore/Files.swift          # scanning, hashing, protections, actions, history
Sources/PurgeCore/SystemMonitor.swift  # Mach/IOKit metrics
Sources/PurgeOS/App.swift              # window, modules, charts, menu bar
Sources/PurgeOS/Model.swift            # scan tasks, state, confirmed actions
Tests/SafetyChecks/main.swift          # standalone checks (Command Line Tools compatible)
Tests/PurgeCoreTests/FilesTests.swift  # XCTest equivalents for Xcode environments
scripts/build-app.sh                   # dependency-free .app packaging
```

`swift run SafetyChecks` checks protected paths, symlinks, prefix boundaries, content duplicates, cancellation, categorization, history and real monitor ranges using disposable generated fixtures for organizer moves, without touching existing user files. XCTest reference tests are included but aren't in the package target because standalone Command Line Tools installations may not ship XCTest.

No RAM-purge button: macOS manages memory; the app monitors it without forcing memory pressure. No automatic cleanup, login registration, privileged daemon or background network activity.
