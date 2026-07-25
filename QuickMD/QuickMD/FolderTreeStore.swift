import SwiftUI

/// Observable store for the root folders browsed by the folder tree
/// sidebar. Multiple roots are supported (insertion order, not sorted —
/// adding a folder shouldn't reorder the ones already there). Only the
/// chosen paths are persisted here — actual security-scoped bookmark
/// storage/restore is delegated to `SandboxAccessManager`, the same
/// mechanism already used for image and linked-file access, so every root
/// is restored silently across relaunches.
@MainActor
final class FolderTreeStore: ObservableObject {
    static let shared = FolderTreeStore()

    private static let rootURLsKey = "FolderTreeRootURLs"

    @Published private(set) var rootURLs: [URL] = []

    /// Which folders are expanded, shared across every open tab/window so
    /// the tree stays in sync no matter which tab you expanded it from. A
    /// root itself is a row in this same scheme — newly added/restored
    /// roots start expanded, matching v1's behavior where the (single) root
    /// folder's contents were always visible without an extra click.
    @Published private(set) var expandedURLs: Set<URL> = []

    /// Per-folder lazy-loaded children, keyed by folder URL — including
    /// root folders, which use this exact same mechanism as any nested
    /// folder rather than a separate top-level list.
    private var childrenCache: [URL: [FolderTreeNode]] = [:]

    /// Single FSEvents stream covering every current root. Recreated (not
    /// incrementally updated) whenever the root set changes — that's a rare,
    /// user-driven event, not a hot path.
    private let treeWatcher = DirectoryTreeWatcher()

    private init() {
        treeWatcher.onChange = { [weak self] in self?.refresh() }
        restoreRootFolders()
    }

    /// Prompt the user to pick a folder and add it to the root list.
    /// Duplicates (by standardized path) are ignored rather than added twice.
    func addRootFolder() {
        guard let url = SandboxAccessManager.shared.pickAndBookmarkFolder() else { return }
        let std = url.standardizedFileURL
        guard !rootURLs.contains(std) else { return }
        addRoot(std)
        persistRootURLs()
        restartWatcher()
    }

    /// Remove a root folder from the list — including its persisted
    /// security-scoped bookmark, so it doesn't linger in `UserDefaults`
    /// forever as an orphaned entry the user can no longer see or clear.
    func removeRootFolder(_ url: URL) {
        let std = url.standardizedFileURL
        rootURLs.removeAll { $0 == std }
        expandedURLs.remove(std)
        childrenCache.removeValue(forKey: std)
        SandboxAccessManager.shared.forgetBookmark(for: std)
        persistRootURLs()
        restartWatcher()
    }

    /// Re-scan everything currently visible (manual refresh, and also what
    /// fires automatically on a live filesystem change — see `treeWatcher`
    /// above). Clears cached subtree listings so every currently-expanded
    /// folder re-scans on next access, then explicitly signals observers —
    /// `childrenCache` isn't itself `@Published` (no need to publish the
    /// tree data a second time), so this is what actually makes every
    /// mounted `FolderTreeRow` re-evaluate and re-fetch via `children(of:)`.
    func refresh() {
        childrenCache.removeAll()
        objectWillChange.send()
    }

    func isExpanded(_ url: URL) -> Bool {
        expandedURLs.contains(url)
    }

    func setExpanded(_ expanded: Bool, for url: URL) {
        if expanded {
            expandedURLs.insert(url)
        } else {
            expandedURLs.remove(url)
        }
    }

    /// Children of `url`, loading and caching them on first access. Used
    /// uniformly for both root folders and nested subfolders.
    func children(of url: URL) -> [FolderTreeNode] {
        if let cached = childrenCache[url] {
            return cached
        }
        let loaded = FolderTreeNode.loadChildren(of: url)
        childrenCache[url] = loaded
        return loaded
    }

    // MARK: - Private

    /// Shared by `addRootFolder` and `restoreRootFolders`: add a root and
    /// default it to expanded (matching v1's always-visible root behavior).
    private func addRoot(_ url: URL) {
        rootURLs.append(url)
        expandedURLs.insert(url)
    }

    private func persistRootURLs() {
        UserDefaults.standard.set(rootURLs.map(\.path), forKey: Self.rootURLsKey)
    }

    /// `DirectoryTreeWatcher.start(watching:)` already stops any previous
    /// stream first and no-ops on an empty array, so restarting on the
    /// current root set is always just this one call.
    private func restartWatcher() {
        treeWatcher.start(watching: rootURLs)
    }

    private func restoreRootFolders() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.rootURLsKey) ?? []
        for path in paths {
            let url = URL(fileURLWithPath: path)
            // Skip (don't block on) a root that's been moved, deleted, or
            // had its access revoked since last launch.
            guard SandboxAccessManager.shared.restoreAccess(for: url) else { continue }
            addRoot(url)
        }
        restartWatcher()
    }
}
