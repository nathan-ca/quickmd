import SwiftUI
import AppKit

// MARK: - Folder Tree Sidebar

/// Left sidebar for browsing a user-chosen folder's markdown files as an
/// expandable tree. Only one root folder is tracked at a time (v1); picking
/// a new folder replaces the current one. Each row loads its own children
/// lazily on first expand, so large trees aren't walked up front.
struct FolderTreeSidebar: View {
    @ObservedObject var store: FolderTreeStore = .shared
    let theme: MarkdownTheme
    let currentURL: URL?
    let onCollapse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if store.rootURL == nil {
                emptyState
            } else if store.rootChildren.isEmpty {
                Spacer(minLength: 0)
                Text("No markdown files found")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(store.rootChildren) { node in
                            FolderTreeRow(node: node, currentURL: currentURL, onOpen: openDocument)
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
            Text(store.rootURL?.lastPathComponent ?? "Folder")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if store.rootURL != nil {
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

                Button {
                    store.pickRootFolder()
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Change folder")
            }

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
            Text("No folder selected")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Button("Add Folder…") {
                store.pickRootFolder()
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
private struct FolderTreeRow: View {
    let node: FolderTreeNode
    let currentURL: URL?
    var depth: Int = 0
    let onOpen: (URL) -> Void
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
                FolderTreeRowLabel(node: node, isCurrent: false)
                    .padding(.leading, CGFloat(depth) * Self.indentPerLevel)
            }
        } else {
            FolderTreeRowLabel(
                node: node,
                isCurrent: currentURL?.standardizedFileURL == node.url.standardizedFileURL
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
        .help(node.url.path)
    }
}
