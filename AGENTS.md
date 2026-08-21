# Kite Agent Guide

## Project scope

Kite is a macOS 13+ SwiftUI process monitor built as a Swift Package.
The GUI product is `Kite`; `kite-cli` is the CLI and
`kite-self-test` is the local integration check. The product and all internal
targets use the Kite name; do not reintroduce the former Swift-based names.

## Architecture

- `Sources/KiteCore`: process enumeration, CPU sampling, process
  signals, and host memory statistics. Keep this target independent of SwiftUI.
- `Sources/KiteApp`: the English-language macOS GUI. Potentially
  blocking system calls belong behind `ProcessService`, not on the main actor.
- `Sources/KiteCLI`: small command-line view of the process provider.
- `Sources/KiteSelfTest`: assertions and live provider smoke tests.

The process provider must retain every PID returned by `proc_listallpids`, even
when macOS denies detailed information. Missing fields should degrade to safe
defaults instead of removing the process. Process-control errors must be shown
to the user because macOS permissions legitimately reject some signals.

## UI conventions

- All user-visible application copy is English.
- Preserve the dense, work-focused process table and persistent system-memory
  summary. Do not replace real host memory statistics with a sum of process RSS.
- Keep sorting on clickable table headers. Refreshing process data must preserve
  the selected sort column and direction. Show resolved account names in the list.
- Present processes as an expandable parent/child tree derived from PID and PPID.
  Keep the tree collapsed initially, preserve expanded rows across automatic refreshes, and reveal ancestor paths for
  search matches. Process context menus include task termination, force quit,
  Finder reveal, and child-first process-tree termination.
- Keep Performance and Processes as peer navigation destinations. Performance
  provides continuously sampled 60-second CPU and memory graphs and host stats.
- Use the shared Activity Monitor-style top bar for peer navigation; do not add
  a page sidebar. Pinned processes stay above the tree in the user's pin order
  across automatic refreshes until explicitly unpinned.
- Prefer a running application's icon, then its containing app bundle icon,
  then the executable/file-type fallback.
- Keep automatic sampling off the main actor and maintain macOS 13 availability.

## Build and verification

Run these after relevant changes:

```sh
swift build
swift run kite-self-test
swift build -c release --product Kite
./scripts/package-app.sh
```

For GUI changes, launch `.build/debug/Kite`, verify that it remains
running, presents a foreground window, and emits no startup warnings.
The distribution artifact is `dist/Kite.app`; set `CODE_SIGN_IDENTITY` when
an ad-hoc or developer signature is required.

`scripts/package-app.sh` creates the macOS app bundle and generates
`AppIcon.icns` at packaging time from `Resources/AppIcon.svg` using the native
Core Graphics generator in `scripts/generate-app-icon.swift`. Do not commit a
generated `.icns` file to `Resources`; the source SVG and generator are the
maintained icon assets.

The bundle currently uses identifier `com.kite.monitor`, version `1.0.0`, and
requires macOS 13 or later. `VERSION`, `BUNDLE_ID`, `OUTPUT_DIR`, and
`CODE_SIGN_IDENTITY` can be provided as environment variables to the packaging
script.

## Keep this file current

**Update `AGENTS.md` in the same change whenever project structure, supported
platforms, architecture, commands, UI language, system-data semantics, or
verification requirements change.** Before finishing any task, explicitly check
whether this guide is still accurate; treating that check as optional will make
future agent work unreliable.
