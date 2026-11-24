import XCTest
@testable import PurgeCore
final class FilesTests: XCTestCase {
    func testProtectedPaths() {
        for path in ["/", "/System/Library", "/Library/Caches/test", NSHomeDirectory(), NSHomeDirectory() + "/Library/Keychains/key", NSHomeDirectory() + "/.ssh/key"] {
            XCTAssertFalse(FileSafety.allowed(URL(fileURLWithPath: path)), path)
        }
        XCTAssertTrue(FileSafety.allowed(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/test.txt")))
    }
    func testScanAndDuplicates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("same".utf8).write(to: root.appendingPathComponent("a"))
        try Data("same".utf8).write(to: root.appendingPathComponent("b"))
        try Data("diff".utf8).write(to: root.appendingPathComponent("c"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: root.appendingPathComponent("a"))
        let files = Scanner.files(in: root)
        XCTAssertEqual(files.count, 3)
        XCTAssertEqual(Scanner.duplicates(files).count, 2)
        XCTAssertEqual(Scanner.files(in: root, cancelled: { true }).count, 0)
        XCTAssertFalse(FileSafety.allowed(root.appendingPathComponent("link"), home: root))
    }
    func testBoundaryAndCategory() {
        XCTAssertFalse(FileSafety.contains(URL(fileURLWithPath: "/Users/me"), URL(fileURLWithPath: "/Users/me-other/file")))
        XCTAssertEqual(Scanner.category(URL(fileURLWithPath: "a.PDF")), "Documents")
    }
}
