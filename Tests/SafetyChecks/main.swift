import Foundation
import PurgeCore
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}
for path in ["/", "/System/Library", "/Library/Caches/test", NSHomeDirectory(), NSHomeDirectory() + "/Library/Keychains/key", NSHomeDirectory() + "/.ssh/key"] {
    check(!FileSafety.allowed(URL(fileURLWithPath: path)), "Protected path allowed: \(path)")
}
let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
let fm = FileManager.default
try fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root) }
for name in ["a", "b"] { try Data("same".utf8).write(to: root.appendingPathComponent(name)) }
try Data("diff".utf8).write(to: root.appendingPathComponent("c"))
try fm.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: root.appendingPathComponent("a"))
check(Scanner.files(in: root).count == 3, "Scanner followed symlink")
check(Scanner.duplicates(Scanner.files(in: root)).count == 2, "Content duplicate detection failed")
check(Scanner.files(in: root, cancelled: { true }).isEmpty, "Cancellation failed")
check(!FileSafety.allowed(root.appendingPathComponent("link"), home: root), "Symlink allowed")
check(!FileSafety.contains(URL(fileURLWithPath: "/Users/me"), URL(fileURLWithPath: "/Users/me-other/file")), "Path prefix bypass")
check(Scanner.category(URL(fileURLWithPath: "test.PDF")) == "Documents", "Category failed")
let actions = FileActions(historyURL: root.appendingPathComponent("history.json"))
let history = try actions.history()
check(history.isEmpty, "Unexpected history")
do { try actions.trash(FileItem(url: URL(fileURLWithPath: "/System"), bytes: 0)); fatalError("Protected trash accepted") } catch {}
let sandbox = fm.homeDirectoryForCurrentUser.appendingPathComponent("PurgeOS-test-" + UUID().uuidString)
try fm.createDirectory(at: sandbox, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: sandbox) }
let document = sandbox.appendingPathComponent("sample.pdf")
try Data("fixture".utf8).write(to: document)
let organizer = FileActions(historyURL: sandbox.appendingPathComponent("history.json"))
try organizer.organize(FileItem(url: document, bytes: 7), downloads: sandbox)
check(fm.fileExists(atPath: sandbox.appendingPathComponent("Documents/sample.pdf").path), "Organizer destination missing")
let entries = try organizer.history()
check(entries.count == 1 && entries[0].action == "Organize", "Move history missing")
try Data("new".utf8).write(to: document)
do { try organizer.organize(FileItem(url: document, bytes: 3), downloads: sandbox); fatalError("Overwrote existing file") } catch {}
check(fm.fileExists(atPath: document.path), "Collision removed source")
let monitor = SystemMonitor(); _ = monitor.sample(); Thread.sleep(forTimeInterval: 0.1)
let sample = monitor.sample()
check(sample.totalRAM > 0, "RAM missing")
check(sample.cpu.map { (0...100).contains($0) } ?? false, "CPU invalid")
print("All safety, scanner, duplicate, history and monitor checks passed.")
