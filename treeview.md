# Folder Tree Sidebar — Implementation Plan

## Goal

A collapsible left-side panel where the user adds a folder and browses its
contents as an expandable tree, showing only markdown files (folders are
always shown, to allow navigating into them). Clicking a file opens it in
QuickMD, same as double-clicking it in Finder.

Also in scope: fix the existing "Recent Documents" sidebar, which currently
has no in-panel way to collapse itself (see "Recent Documents collapse fix"
below) — found while designing this panel's header, and worth fixing
alongside it so both sidebars behave consistently.

## v1 Scope (agreed)

- **One root folder at a time.** Adding a new folder replaces the current one.
  Multi-root ("workspaces") is a natural v2, not v1.
- **Filter: `md`, `markdown`, `mdown`, `mkd` extensions** (case-insensitive).
  This matches the exact set of extensions QuickMD's own `Info.plist`
  already declares as openable (all mapped to the `net.daringfireball.markdown`
  UTI) — so the tree never hides a file the app can otherwise open via
  double-click or ⌘O. Folders are always shown regardless of contents, so the
  user can navigate into them.
- **Manual refresh**, not live filesystem watching. A refresh button/menu
  item re-scans the tree. Live updates (new/renamed/deleted files reflected
  automatically) are a v2 addition — see "Explicitly out of scope" below.
- **Independent toggle panel**, shown alongside the existing "Recent
  Documents" sidebar rather than replacing or tabbing with it. Simpler to
  build, and consistent with how Documents/ToC are already independent
  toggles. *(Confirmed.)*

## What already exists and gets reused

The app already has the load-bearing pieces for this; most of the work is
new UI + a data model, not new infrastructure.

- **Collapsible/resizable sidebar pattern** — `MarkdownView.swift` already
  drives this via `@AppStorage` visibility flags (`isDocumentListVisible`,
  `isToCVisible`) plus `.transition(.move(edge: .leading)...)` and the
  existing `SidebarResizeHandle` (`Views/RecentDocumentsSidebar.swift`). The
  new panel slots into the same `HStack` in `MarkdownView.body` the same way.
- **Security-scoped folder access** — `SandboxAccessManager.swift` already
  does `NSOpenPanel` directory picking, bookmark persistence, and silent
  restore on relaunch. It's currently only exposed as
  `ensureAccess(forParentOf: fileURL)` (derives the parent dir of a file);
  needs one new public entry point that operates on a directory the user
  picks directly (see "New/changed files" below).
- **Opening a file from a row** — `RecentDocumentsSidebar.openDocument(_:)`
  already does this via `NSWorkspace.shared.open([url], withApplicationAt:
Bundle.main.bundleURL, ...)`, which correctly merges into the existing tab
  group via `WindowTabbing.swift`. The tree view reuses this verbatim.
- **Persisted state pattern** — `RecentDocumentsStore` is the template for a
  small `ObservableObject` backed by `UserDefaults`; the new folder-root
  store follows the same shape.

## What's genuinely new

### 1. `SandboxAccessManager.swift` (modify)

Add a public method to pick a folder and bookmark it directly, e.g.:

```swift
func pickAndBookmarkFolder() -> URL?
```

Refactors the existing private `promptForAccess(to:)` panel-and-bookmark
logic into something callable from the "Add Folder" button, instead of only
being reachable via the image-access-denied retry path.

### 2. `FolderTreeNode.swift` (new — data model)

Plain value type, recursively describing the tree:

```swift
struct FolderTreeNode: Identifiable {
    let id: URL           // file URL, already unique
    let url: URL
    let name: String
    let isDirectory: Bool
    var children: [FolderTreeNode]?   // nil = not yet loaded / leaf
}
```

Lazy-loaded: children are only enumerated when a folder is expanded (avoids
walking a huge tree up front). A pure, unit-testable function builds one
level of children from a directory URL:

```swift
static func loadChildren(of directoryURL: URL) -> [FolderTreeNode]
```

Filtering rule for this function: keep entries that are either directories,
or files whose extension (case-insensitive) is one of `md`, `markdown`,
`mdown`, `mkd`. Skip dotfiles. Sort: folders first, then files,
alphabetically — matches Finder's default and users' expectations.

### 3. `FolderTreeStore.swift` (new — persistence)

Holds the single root folder URL, persisted in `UserDefaults` (bookmark
data, same mechanism as `SandboxAccessManager`), restored silently at
launch via `SandboxAccessManager.restoreAccess(for:)`. Shape mirrors
`RecentDocumentsStore`.

### 4. `Views/FolderTreeSidebar.swift` (new — UI)

- Header row: folder name (or "Add Folder" empty state), refresh button,
  "change folder" button, and a **collapse button** (see item 7) — same
  visual language as `RecentDocumentsSidebar`'s header (icon + label +
  trailing action buttons).
- Tree body: `OutlineGroup` (or nested `DisclosureGroup`s) over
  `FolderTreeNode`, lazy-expanding via `loadChildren`. Row styling reuses
  `DocumentRow`'s look (doc icon, hover highlight, click-to-open) — likely
  worth extracting a shared row style rather than duplicating it.
- Empty state: "No folder selected" / "No markdown files found" — same
  pattern as `RecentDocumentsSidebar`'s empty state text.

### 5. `MarkdownView.swift` (modify)

- New `@AppStorage("isFolderTreeVisible")` flag + `@AppStorage
("folderTreeWidth")`, following `isDocumentListVisible` /
  `documentListWidth` exactly.
- Render `FolderTreeSidebar` in the leading `HStack`, with its own
  `SidebarResizeHandle`.

### 6. `QuickMDApp.swift` (modify)

- New `FocusedValue` (`toggleFolderTreeAction`) + `ToggleFolderTreeCommand`
  button, mirroring `ToggleDocumentListCommand`. Shortcut: **`⌘⇧V`**
  *(confirmed — `⌘⇧D` is Documents, `⌘⇧T` is ToC, both already taken)*.

### 7. `Views/RecentDocumentsSidebar.swift` (modify) — collapse fix

Today `isDocumentListVisible` can only be set to `false` via the `⌘⇧D` menu
shortcut — there's a floating "show" button (`sidebar.leading` icon,
`MarkdownView.swift` ~line 153) that appears when the panel is hidden, but
nothing symmetric in the panel itself to hide it again once open. That's the
"not collapsable" gap.

Fix: add a small collapse button to `RecentDocumentsSidebar`'s header row
(next to the existing trash/clear button), taking a new `onCollapse: () ->
Void` closure that `MarkdownView` wires to
`withAnimation(.easeInOut(duration: 0.2)) { isDocumentListVisible = false }`
— same animation the reveal button already uses. `FolderTreeSidebar`'s
header (item 4) gets the same button from the start, so both panels behave
identically. Since both headers now share icon + title + trailing
collapse-button structure, worth factoring out a small shared
`SidebarHeader` view rather than duplicating the layout twice — optional
polish, not required for correctness.

## Suggested build order

1. `SandboxAccessManager` — add the direct-folder-pick entry point.
2. `FolderTreeNode` + `loadChildren` — pure logic, write unit tests first
   (`QuickMDTests/`, matching the existing `ParserTests`/`SearchTests`
   style) since it's the one piece with real filtering logic to get right.
3. `FolderTreeStore` — persistence.
4. `RecentDocumentsSidebar` — add the collapse button + `onCollapse` closure
   (small, independent fix — can land on its own before the rest).
5. `FolderTreeSidebar` — UI, wired to the store, header matches the now-fixed
   `RecentDocumentsSidebar` pattern.
6. `MarkdownView` — layout integration + toggle state for both sidebars.
7. `QuickMDApp` — menu command + `⌘⇧V` keyboard shortcut.
8. Manual QA: add a folder, expand/collapse, open a file, quit and relaunch
   (bookmark restore), rename/delete a file on disk then hit refresh; collapse
   both sidebars via their in-panel buttons and via keyboard shortcuts.

## Explicitly out of scope for v1 (flagged, not decided against)

- **Multiple root folders** — store would need to become `[URL]` instead of
  `URL`, and the UI would need per-root grouping. Deferred.
- **Live tree updates** — would need a recursive directory watcher.
  `FileWatchManager.swift` currently watches exactly one file via a kqueue
  `DispatchSource`; watching an entire tree is a materially different
  problem (either many kqueue watches or a switch to FSEvents) and is its
  own follow-up piece of work, not a small extension.
- **Hiding folders that contain no `.md` files anywhere in their subtree** —
  would require eagerly walking the full tree instead of lazy per-level
  loading, which conflicts with lazy expansion for large directories.
  Default: show all folders regardless of content.

## Decisions

1. Keyboard shortcut for the toggle: **`⌘⇧V`**.
2. Independent panel vs. combining with the existing Documents sidebar
   behind a tab/segmented control: **independent**, confirmed for v1.

## Status: v1 shipped

Multi-round polish already landed on top of the original plan: the
extension filter, indentation/alignment fixes, and moving expand-state +
loaded-children from per-tab `@State` into `FolderTreeStore` so every open
tab shows the same tree (see conversation history — not re-derived here).

---

# v2: Multiple root folders + live tree updates

Picking up exactly the two items flagged "explicitly out of scope" above.
The third (hiding folders with no markdown anywhere in their subtree)
remains out of scope — not requested for v2.

## Multiple root folders

- `FolderTreeStore.rootURL: URL?` → `rootURLs: [URL]` (insertion order, not
  sorted — matches how VS Code's multi-root workspaces behave, and avoids
  surprising reordering when you add a folder).
- `rootChildren: [FolderTreeNode]` → `rootChildrenByURL: [URL: [FolderTreeNode]]`,
  one top-level listing per root.
- `pickRootFolder()` (replace-the-one-root semantics) → `addRootFolder()`
  (appends, skips duplicates by standardized path) + `removeRootFolder(_:)`.
  Removing a root also deletes its `SandboxAccessManager` bookmark from
  `UserDefaults` rather than leaving an orphaned entry behind.
- Persistence: `UserDefaults` array of path strings instead of one string;
  restore loops over each, skipping (not blocking on) any folder that's
  been moved/deleted/had access revoked since last launch.
- UI: the single-folder header (name + refresh/change/collapse) becomes a
  generic panel header (title + "Add Folder" + collapse), and each root
  gets its own row within the scrollable list — reusing the same
  disclosure-row mechanism as nested folders (so a root can itself be
  collapsed to hide its tree), plus a remove button a plain folder row
  doesn't have. Global refresh button re-scans every root, not per-root —
  simpler, and re-scanning a top-level directory listing is cheap.
- `SandboxAccessManager` needs no changes — `pickAndBookmarkFolder()`/
  `restoreAccess(for:)` already operate per-URL generically.

## Live tree updates

Confirmed in v1 planning: `FileWatchManager`'s kqueue approach doesn't
scale to a whole tree (one descriptor per file, no recursion). Using
**FSEvents** instead (`CoreServices`, public API — recursive tree
watching in one stream per set of root paths, which kqueue can't do at
all). New `DirectoryTreeWatcher.swift`, shaped like `FileWatcher.swift`
(debounced `onChange` callback, main-queue by construction, deliberately
not `@MainActor` for the same toolchain-compatibility reason documented in
`FileWatcher.swift`) but backed by `FSEventStreamCreate` instead of a
`DispatchSourceFileSystemObject`.

Design choices, and why:
- **One stream for all roots, not one per root.** `FSEventStreamCreate`
  accepts an array of paths natively; recreated (stop + start fresh) only
  when the root set changes (add/remove), which is a rare, user-driven
  event — not a hot path.
- **Treat any event as "something changed, refresh everything currently
  visible."** No attempt to diff which specific node changed and patch
  just that part of the tree. Simpler, and directory listings are cheap
  enough that a full refresh on change is not a performance concern for a
  markdown-file browser. Reuses the *exact* existing `refresh()` path —
  live updates are not a separate code path from clicking the refresh
  button, just a different trigger for the same method.
- **Default FSEvents flags** (`kFSEventStreamCreateFlagNone`), not
  `kFSEventStreamCreateFlagFileEvents`/`UseCFTypes` — those exist to get
  per-file event detail, which isn't needed since we're not inspecting
  individual event paths.
- **Debounced** (matching `FileWatcher`'s 250ms pattern) so a burst of
  saves (e.g. a git checkout touching many files) coalesces into one
  refresh instead of many.

## Suggested build order (v2)

1. `FolderTreeStore` — `rootURLs`/`rootChildrenByURL`, add/remove methods,
   multi-path persistence + restore.
2. `Views/FolderTreeSidebar.swift` — header restructure, per-root row with
   remove button, reusing the existing disclosure-row mechanism.
3. `DirectoryTreeWatcher.swift` — FSEvents wrapper.
4. Wire the watcher into `FolderTreeStore`: start/restart on root-set
   changes, `onChange` calls the existing `refresh()`.
5. Manual QA: add 2+ roots, confirm both persist across relaunch; remove
   one, confirm its bookmark is cleaned up (not just hidden); with the app
   running, create/rename/delete a `.md` file in a watched folder via
   Finder/Terminal and confirm the tree updates without touching the
   refresh button.

## Status: v2 implemented, awaiting QA

All of the above is built:
`FolderTreeStore` moved to `rootURLs`/`addRootFolder`/`removeRootFolder`,
`Views/FolderTreeSidebar.swift` restructured (generic header, per-root
rows with a remove button, reusing the same disclosure-row mechanism as
nested folders), `DirectoryTreeWatcher.swift` added and wired into
`FolderTreeStore` so both manual refresh and live filesystem changes go
through the same `refresh()` path. Not yet run through the manual QA list
above — no unit tests were added for `DirectoryTreeWatcher` itself
(FSEvents delivery timing is inherently unreliable to assert on in an
automated test; this is exactly the kind of thing manual QA is for).

## Known follow-ups (deliberately not done)

From a `/simplify` pass before check-in — real findings, judged out of
scope for a cleanup pass because each would change behavior or touch
stable code well outside this diff:

- **`refresh()` clears the entire `childrenCache`, for every root, on
  every single FSEvents change** — even one scoped to a single file in one
  small corner of one root's tree. This is the plan's original "any event
  means refresh everything visible" design (see "Live tree updates"
  above), not an oversight, but it does mean a change anywhere forces a
  disk re-scan of every previously-expanded folder everywhere. Scoping it
  down would mean threading FSEvents' actual changed-path data (currently
  discarded in `DirectoryTreeWatcher`'s callback) through to `refresh()`
  and only invalidating cache entries that are the changed path or a
  descendant of it. Worth doing if live-update performance on large,
  frequently-changing trees ever becomes a real complaint — not before.
- **`DirectoryTreeWatcher`, `FileWatcher` (`FileWatchManager.swift`), and
  `MarkdownView`'s search-text debounce all independently implement the
  same cancel-and-reschedule `DispatchWorkItem` debounce pattern.** A
  shared `Debouncer` utility would remove the duplication, but doing it
  means modifying `FileWatcher` — stable code this diff never touched —
  for a stylistic win. Not worth the regression risk in a pre-check-in
  cleanup; a candidate for its own deliberate, tested refactor later.
- **`FolderTreeStore.removeRootFolder` doesn't coordinate with
  `OpenDocumentsStore` before revoking sandbox access to a folder.** If a
  document from inside that folder is currently open in a tab, removing
  the folder can leave that document unable to be reopened later — this
  is the same root cause as the `CLAUDE.md` reopen-permission crash (see
  `session-restore.md`'s "Known follow-ups" for the fuller writeup).
  Flagged as a design question, not resolved: should removing a root
  check for open documents underneath it first?
