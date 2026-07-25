import SwiftUI
import AppKit

// MARK: - Folder Tree Sidebar

/// Left sidebar for browsing one or more user-chosen folders' markdown
/// files as expandable trees. Each root folder is its own top-level row
/// (removable, independently collapsible); each directory row loads its
/// own children lazily on first expand, so large trees aren't walked up
/// front. Updates live as files change on disk (`FolderTreeStore`'s
/// `DirectoryTreeWatcher`), not just on manual refresh.
struct FolderTreeSidebar: View {
    @ObservedObject var store: FolderTreeStore = .shared
    let theme: MarkdownTheme
    let currentURL: URL?
    let onCollapse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if store.rootURLs.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(store.rootURLs, id: \.self) { rootURL in
                            FolderTreeRow(
                                node: FolderTreeNode(url: rootURL, isDirectory: true),
                                currentURL: currentURL,
                                onOpen: openDocument,
                                onRemove: { store.removeRootFolder(rootURL) }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .background(theme.backgroundColor.opacity(0.5))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text("Folders")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            Spacer()

            if !store.rootURLs.isEmpty {
                Button {
                    store.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }

            Button {
                store.addRootFolder()
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Add Folder")

            Button(action: onCollapse) {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Hide folder browser")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            Text("No folders added yet")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Button("Add Folder…") {
                store.addRootFolder()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
    }

    private func openDocument(_ url: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: Bundle.main.bundleURL,
            configuration: config,
            completionHandler: { _, error in
                if let error = error {
                    assertionFailure("Folder tree open failed: \(error.localizedDescription)")
                }
            }
        )
    }
}

// MARK: - Row

/// Recursive row: a directory renders as a disclosure group whose children
/// are loaded on first expand; a file renders as a leaf, tap-to-open.
/// `onRemove` is only ever set for a root-level row (passed down from
/// `FolderTreeSidebar`) — recursive calls for nested children always
/// default it to `nil`, so only roots get a remove button.
private struct FolderTreeRow: View {
    let node: FolderTreeNode
    let currentURL: URL?
    var depth: Int = 0
    let onOpen: (URL) -> Void
    var onRemove: (() -> Void)? = nil
    @ObservedObject private var store: FolderTreeStore = .shared

    /// Per-level indent. Applied explicitly here rather than relying on
    /// DisclosureGroup's own indentation — nested DisclosureGroups don't
    /// reliably indent their content on macOS, so each row computes its own
    /// absolute depth-based offset instead of stacking relative insets.
    private static let indentPerLevel: CGFloat = 14

    /// Expand state and loaded children live in the shared store (not local
    /// @State) so every open tab's tree shows the same expanded folders —
    /// each tab renders its own view hierarchy, so per-row @State would
    /// otherwise be invisible to every other tab.
    private var isExpandedBinding: Binding<Bool> {
        Binding(
            get: { store.isExpanded(node.url) },
            set: { store.setExpanded($0, for: node.url) }
        )
    }

    var body: some View {
        if node.isDirectory {
            DisclosureGroup(isExpanded: isExpandedBinding) {
                if store.isExpanded(node.url) {
                    ForEach(store.children(of: node.url)) { child in
                        FolderTreeRow(node: child, currentURL: currentURL, depth: depth + 1, onOpen: onOpen)
                    }
                }
            } label: {
                FolderTreeRowLabel(node: node, isCurrent: false, onRemove: onRemove)
                    .padding(.leading, CGFloat(depth) * Self.indentPerLevel)
            }
        } else {
            FolderTreeRowLabel(
                node: node,
                isCurrent: currentURL?.standardizedFileURL == node.url.standardizedFileURL,
                onRemove: nil
            )
            // Files have no disclosure triangle, so add its approximate width
            // (~16pt) on top of the depth indent to align file names under
            // their parent folder's name rather than under its triangle.
            .padding(.leading, CGFloat(depth) * Self.indentPerLevel + 16)
            .contentShape(Rectangle())
            .onTapGesture { onOpen(node.url) }
        }
    }
}

private struct FolderTreeRowLabel: View {
    let node: FolderTreeNode
    let isCurrent: Bool
    let onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: node.isDirectory ? "folder" : "doc.plaintext")
                .font(.system(size: 11))
                .foregroundColor(isCurrent ? .accentColor : .secondary)
            Text(node.name)
                .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove folder")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
        .help(node.url.path)
    }
}
