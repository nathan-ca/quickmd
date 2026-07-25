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

    private init() {
        restoreRootFolder()
    }

    /// Prompt the user to pick a folder, replacing the current root (if any).
    func pickRootFolder() {
        guard let url = SandboxAccessManager.shared.pickAndBookmarkFolder() else { return }
        rootURL = url
        UserDefaults.standard.set(url.standardizedFileURL.path, forKey: Self.rootURLKey)
        refresh()
    }

    /// Re-scan the current root folder's top level (manual refresh).
    func refresh() {
        guard let rootURL else { return }
        rootChildren = FolderTreeNode.loadChildren(of: rootURL)
    }

    private func restoreRootFolder() {
        guard let path = UserDefaults.standard.string(forKey: Self.rootURLKey) else { return }
        let url = URL(fileURLWithPath: path)
        guard SandboxAccessManager.shared.restoreAccess(for: url) else { return }
        rootURL = url
        refresh()
    }
}
