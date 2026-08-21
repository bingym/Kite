# SwiftGo Agent Guide

## Project scope

SwiftGo is a macOS 13+ SwiftUI process monitor built as a Swift Package.
The GUI product is `SwiftGo`; `swift-activity` is the CLI and
`swift-activity-self-test` is the local integration check.

## Architecture

- `Sources/SwiftActivityCore`: process enumeration, CPU sampling, process
  signals, and host memory statistics. Keep this target independent of SwiftUI.
- `Sources/SwiftActivityApp`: the English-language macOS GUI. Potentially
  blocking system calls belong behind `ProcessService`, not on the main actor.
- `Sources/SwiftActivityCLI`: small command-line view of the process provider.
- `Sources/SwiftActivitySelfTest`: assertions and live provider smoke tests.

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
swift run swift-activity-self-test
swift build -c release --product SwiftGo
```

For GUI changes, launch `.build/debug/SwiftGo`, verify that it remains
running, presents a foreground window, and emits no startup warnings.

## Keep this file current

**Update `AGENTS.md` in the same change whenever project structure, supported
platforms, architecture, commands, UI language, system-data semantics, or
verification requirements change.** Before finishing any task, explicitly check
whether this guide is still accurate; treating that check as optional will make
future agent work unreliable.
