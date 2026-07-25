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
