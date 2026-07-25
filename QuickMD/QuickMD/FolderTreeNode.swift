import Foundation

// MARK: - Folder Tree Node

/// One entry in the folder tree sidebar: either a directory (always shown,
/// so the user can navigate into it) or a markdown file. Files with any
/// other extension are filtered out by `loadChildren(of:)`.
struct FolderTreeNode: Identifiable, Hashable {
    let id: URL
    let url: URL
    let name: String
    let isDirectory: Bool

    /// Children of a directory node, loaded lazily via `loadChildren(of:)`.
    /// `nil` for file nodes, and for directory nodes not yet expanded.
    var children: [FolderTreeNode]?

    init(url: URL, isDirectory: Bool, children: [FolderTreeNode]? = nil) {
        self.id = url
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = isDirectory
        self.children = children
    }
}

extension FolderTreeNode {
    /// Extensions QuickMD treats as markdown — matches exactly what
    /// Info.plist declares as openable via the `net.daringfireball.markdown`
    /// UTI, so the tree never hides a file the app can otherwise open.
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]

    /// Build one level of the tree: every subdirectory, plus every markdown
    /// file, directly inside `directoryURL`. Does not recurse — subdirectory
    /// children are loaded lazily when expanded in the UI. Hidden
    /// (dotfile-prefixed) entries are skipped. Folders sort before files;
    /// each group is alphabetical (case-insensitive), matching Finder.
    static func loadChildren(of directoryURL: URL) -> [FolderTreeNode] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let nodes: [FolderTreeNode] = contents.compactMap { url in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                return FolderTreeNode(url: url, isDirectory: true)
            }
            guard markdownExtensions.contains(url.pathExtension.lowercased()) else {
                return nil
            }
            return FolderTreeNode(url: url, isDirectory: false)
        }

        return nodes.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
