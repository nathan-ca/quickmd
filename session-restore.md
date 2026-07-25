# Session Restore — Implementation Plan

## Goal

On launch, QuickMD should reopen whatever was open when it last quit (open
document tabs, and the folder tree's root folder) instead of always showing
an Open panel. If there's nothing to restore (first launch, or the user
closed everything before quitting), fall back to exactly today's behavior —
that fallback needs no new code, it's what already happens.

## Diagnosis (why this doesn't happen today)

Two separate causes, addressed separately below:

1. **Root folder isn't eagerly restored.** `FolderTreeStore.shared` is a
   lazily-initialized singleton — `restoreRootFolder()` only runs the first
   time some view touches `.shared`. If the app launches straight to the
   Open panel with zero document windows, `FolderTreeSidebar` never gets
   created, so the store never initializes, so the already-persisted
   bookmark never gets restored. The data survives; nothing asks for it.
2. **Open tabs aren't tracked or restored at all.** `MarkdownDocument`
   conforms to `FileDocument` via `DocumentGroup(viewing:)` — the
   "viewer" flavor of SwiftUI's document API. Unlike editable
   `DocumentGroup(newDocument:)` apps, this flavor doesn't get automatic
   window/state restoration from the system the way TextEdit does. There's
   also no app delegate at all today (no `NSApplicationDelegateAdaptor` in
   `QuickMDApp.swift`), and `RecentDocumentsStore` tracks _history_ of
   opened files (capped at 50, doesn't distinguish open from closed) — not
   "what's open right now." There's currently no data to restore from even
   if restoration worked.

## v1 Scope

- Restore the root folder eagerly at launch (independent, low-risk, ships
  on its own).
- Restore document tabs that were open at quit time.
- No attempt to restore window position/size, scroll position, ToC/sidebar
  states per-document, or which tab was frontmost — just "which files were
  open." Those are natural follow-ups, not v1.
- Falling back to today's Open-panel-on-launch when there's nothing
  persisted is the existing default behavior — explicitly not something to
  build, just something to not break.

## What already exists and gets reused

- **Bookmark/restore mechanism for the folder** — `FolderTreeStore` and
  `SandboxAccessManager` already do this correctly; only the _timing_ of
  when it runs needs to change (eager vs. lazy).
- **Reopening a file by URL** — `RecentDocumentsSidebar.openDocument(_:)`
  already does this via `NSWorkspace.shared.open([url], withApplicationAt:
Bundle.main.bundleURL, ...)`, relying on the system's implicit
  security-scoped access for files the user has legitimately opened before
  (the same "powerbox" mechanism that already lets Recent Documents reopen
  files without QuickMD managing per-file bookmarks itself). Reopening
  previously-open tabs at launch can lean on this same mechanism — no new
  per-file bookmark infrastructure needed, since these are all files the
  user already opened through the system at least once.

## What's genuinely new

### 1. `QuickMDApp.swift` — eager `FolderTreeStore` init

Touch `FolderTreeStore.shared` in `QuickMDApp.init()` so
`restoreRootFolder()` runs regardless of whether any document window opens.
Trivial, one line, no new files.

### 2. Track currently-open documents

Need a small new store (e.g. `OpenDocumentsStore`, shape modeled on
`RecentDocumentsStore`) holding the set of URLs currently open in a tab —
distinct from "ever opened" history. Register on open, unregister on close.
Simplest hook: `MarkdownView.onAppear`/`.onDisappear` (each window hosts
exactly one `MarkdownView` for its lifetime here, so this should correlate
reliably with tab/window open-close — worth confirming during QA that a tab
switch or view re-layout doesn't spuriously fire `onDisappear`).

### 3. Persist across launches

Write the open-URL set to `UserDefaults` (path strings, like
`FolderTreeStore`'s root-folder key) whenever it changes.

### 4. `NSApplicationDelegateAdaptor` — intercept launch

This app has no delegate today; this is new plumbing. In
`applicationWillFinishLaunching` (before `NSDocumentController` decides
whether to show the default Open panel), read the persisted URL set and, if
non-empty, open each one via `NSDocumentController.shared.openDocument
(withContentsOf:display:completionHandler:)`. If empty, do nothing — the
existing default Open-panel behavior takes over unchanged.

## Suggested build order

1. `QuickMDApp.swift` — eager `FolderTreeStore.shared` touch (ships alone,
   low risk, immediately fixes the "root folder not restored" symptom).
2. `OpenDocumentsStore` — new store, wired into `MarkdownView`'s
   appear/disappear.
3. `NSApplicationDelegateAdaptor` + launch-time reopen logic.
4. Manual QA (see risks below — this part needs hands-on verification more
   than anything else built so far in this project).

## Risks / things I can't verify without building this

- **Ordering between our delegate and the launch-time Open-panel decision.**
  Confirmed real, and confirmed **not fixable through supported API.** The
  reopen calls in `applicationWillFinishLaunching` are async (reading a file
  and building a window takes a moment), and `DocumentGroup(viewing:)` shows
  its own Open panel the instant its scene first evaluates with zero open
  documents — a SwiftUI-internal decision. Traced with logging to confirm:
  `applicationShouldOpenUntitledFile` (the classic AppKit hook for exactly
  this situation) is **never called** for this document type, so
  implementing it to return `false` was a dead end — verified via a build
  with tracing, not assumed. The only other lever considered
  (`NSApp.setActivationPolicy(.prohibited)` to hide all windows until the
  restored one is ready, then reveal) was rejected: even though it's public
  API, using it to paper over a framework limitation like this is exactly
  the kind of fighting-the-platform hack that's fragile and risks App
  Review friction for an uncertain, purely cosmetic payoff. **Accepted as a
  known limitation** — the actual restore is correct and user-verified; a
  brief Open-panel flash before it auto-dismisses is the tradeoff.
- **`onDisappear` reliability as a "tab closed" signal** — turned out to be
  reliable as a signal, but the naive version was wrong regardless: quitting
  the app closes every window, firing the same `onDisappear` as a
  user-closed tab, which was unregistering every open document right before
  quit and leaving nothing to restore. Fixed with an `AppDelegate
  .isTerminating` flag set in `applicationShouldTerminate` (fires before
  AppKit starts closing windows), checked in `onDisappear` to skip
  unregistering during quit specifically.
- **Multiple simultaneous windows/tabs at quit time** — confirmed working
  (user-verified: reopens previously-open tabs correctly).

## Explicitly out of scope for v1

- Window position/size restoration.
- Restoring which tab was frontmost / active.
- Per-document UI state (scroll position, ToC visibility, search state).
- Folder tree expand/collapse state persistence across launches (currently
  in-memory only via `FolderTreeStore.expandedURLs`, resets each launch —
  could persist the same way as the root folder, but not asked for here).

## Decisions

1. Store name: **`OpenDocumentsStore`**, confirmed.
2. Built the simple `applicationWillFinishLaunching` approach first, as
   agreed — the double-Open-panel race turned out to be real (see Risks),
   but the fix attempted for it turned out to be a dead end, and the
   remaining API-level workaround was rejected on App Review risk grounds.
   Landed on accepting the cosmetic flash rather than chasing it further.

## Status: shipped, with one known cosmetic limitation

Both the root-folder eager restore and open-tab session restore are in
place and user-verified working (including the quit-time unregister bug).
The one open item is a brief Open-panel flash on launch when there's
something to restore — cosmetic only, not a functional bug, and not
fixable through documented API (see Risks above).

Both fixes (`applicationShouldTerminate`/`isTerminating` guard, and
`applicationShouldOpenUntitledFile` suppression) are in place and
user-verified working, including the previously-visible Open-panel flash.
