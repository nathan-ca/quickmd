import SwiftUI

/// Observable store for the single root folder browsed by the folder tree
/// sidebar (v1 tracks one root at a time; picking a new folder replaces the
/// current one). Only the chosen path is persisted here — actual
/// security-scoped bookmark storage/restore is delegated to
/// `SandboxAccessManager`, the same mechanism already used for image and
/// linked-file access, so the folder is restored silently across relaunches.
@MainActor
final class FolderTreeStore: ObservableObject {
    static let shared = FolderTreeStore()

    private static let rootURLKey = "FolderTreeRootURL"

    @Published private(set) var rootURL: URL?
    @Published private(set) var rootChildren: [FolderTreeNode] = []

    /// Which folders are expanded, shared across every open tab/window so
    /// the tree stays in sync no matter which tab you expanded it from.
    @Published private(set) var expandedURLs: Set<URL> = []

    /// Per-folder lazy-loaded children, keyed by folder URL. Shared for the
    /// same reason as `expandedURLs` — also means expanding the same folder
    /// in two tabs only scans the directory once, not once per tab.
    private var childrenCache: [URL: [FolderTreeNode]] = [:]

    private init() {
        restoreRootFolder()
    }

    /// Prompt the user to pick a folder, replacing the current root (if any).
    func pickRootFolder() {
        guard let url = SandboxAccessManager.shared.pickAndBookmarkFolder() else { return }
        rootURL = url
        expandedURLs.removeAll()
        childrenCache.removeAll()
        UserDefaults.standard.set(url.standardizedFileURL.path, forKey: Self.rootURLKey)
        refresh()
    }

    /// Re-scan the whole tree (manual refresh) — clears cached subtree
    /// listings so every currently-expanded folder re-scans on next access.
    func refresh() {
        guard let rootURL else { return }
        childrenCache.removeAll()
        rootChildren = FolderTreeNode.loadChildren(of: rootURL)
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

    /// Children of `url`, loading and caching them on first access.
    func children(of url: URL) -> [FolderTreeNode] {
        if let cached = childrenCache[url] {
            return cached
        }
        let loaded = FolderTreeNode.loadChildren(of: url)
        childrenCache[url] = loaded
        return loaded
    }

    private func restoreRootFolder() {
        guard let path = UserDefaults.standard.string(forKey: Self.rootURLKey) else { return }
        let url = URL(fileURLWithPath: path)
        guard SandboxAccessManager.shared.restoreAccess(for: url) else { return }
        rootURL = url
        refresh()
    }
}
