import XCTest

/// FolderTreeNode.loadChildren tests: extension filtering (md/markdown/mdown/mkd
/// only, matching Info.plist's declared UTI extensions), folder-first sorting,
/// and hidden-file exclusion.
final class FolderTreeNodeTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("quickmd-tree-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func touch(_ name: String, in directory: URL? = nil) throws {
        try "".write(to: (directory ?? tempDir).appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func testOnlyMarkdownExtensionsAreKept() throws {
        try touch("notes.md")
        try touch("readme.markdown")
        try touch("legacy.mdown")
        try touch("old.mkd")
        try touch("image.png")
        try touch("script.swift")

        let names = Set(FolderTreeNode.loadChildren(of: tempDir).map(\.name))
        XCTAssertEqual(names, ["notes.md", "readme.markdown", "legacy.mdown", "old.mkd"])
    }

    func testExtensionMatchIsCaseInsensitive() throws {
        try touch("SHOUTING.MD")

        let names = FolderTreeNode.loadChildren(of: tempDir).map(\.name)
        XCTAssertEqual(names, ["SHOUTING.MD"])
    }

    func testSubdirectoriesAreAlwaysIncludedRegardlessOfContents() throws {
        let emptySubfolder = tempDir.appendingPathComponent("empty-subfolder")
        let noMarkdownSubfolder = tempDir.appendingPathComponent("no-markdown-here")
        try FileManager.default.createDirectory(at: emptySubfolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: noMarkdownSubfolder, withIntermediateDirectories: true)
        try touch("notes.txt", in: noMarkdownSubfolder)

        let nodes = FolderTreeNode.loadChildren(of: tempDir)
        XCTAssertEqual(Set(nodes.map(\.name)), ["empty-subfolder", "no-markdown-here"])
        XCTAssertTrue(nodes.allSatisfy(\.isDirectory))
    }

    func testFoldersSortBeforeFilesThenAlphabetically() throws {
        try touch("zebra.md")
        try touch("apple.md")
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("Middle"),
            withIntermediateDirectories: true
        )

        let names = FolderTreeNode.loadChildren(of: tempDir).map(\.name)
        XCTAssertEqual(names, ["Middle", "apple.md", "zebra.md"])
    }

    func testHiddenFilesAreSkipped() throws {
        try touch(".hidden.md")
        try touch("visible.md")

        let names = FolderTreeNode.loadChildren(of: tempDir).map(\.name)
        XCTAssertEqual(names, ["visible.md"])
    }

    func testChildrenStartNilUntilLoaded() {
        let node = FolderTreeNode(url: tempDir, isDirectory: true)
        XCTAssertNil(node.children)
    }
}
