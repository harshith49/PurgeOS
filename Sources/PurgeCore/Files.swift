import Foundation
import CryptoKit

public struct FileItem: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let bytes: Int64
    public let modified: Date
    public let group: String
    public init(url: URL, bytes: Int64, modified: Date = .distantPast, group: String = "") {
        self.url = url; self.bytes = bytes; self.modified = modified; self.group = group
    }
}
public enum FileSafety {
    public static func contains(_ root: URL, _ url: URL) -> Bool {
        let r = root.standardizedFileURL.path, p = url.standardizedFileURL.path
        return p.hasPrefix(r + "/")
    }
    public static func allowed(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let original = url.standardizedFileURL
        let resolved = original.resolvingSymlinksInPath()
        guard original.path == resolved.path, original.path != home.path else { return false }
        let apps = URL(fileURLWithPath: "/Applications")
        if original.deletingLastPathComponent() == apps { return original.pathExtension == "app" }
        guard contains(home, original) else { return false }
        let library = home.appendingPathComponent("Library")
        if original == library { return false }
        if contains(library, original) {
            return ["Caches", "Logs"].contains { contains(library.appendingPathComponent($0), original) }
        }
        return ![".ssh", ".gnupg", ".Trash", "Applications"].contains { name in
            let protected = home.appendingPathComponent(name)
            return original == protected || contains(protected, original)
        }
    }
}
public enum Scanner {
    public static func files(in root: URL, cancelled: () -> Bool = { false }, issue: @escaping (String) -> Void = { _ in }) -> [FileItem] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .isUbiquitousItemKey]
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { url, error in issue("\(url.path): \(error.localizedDescription)"); return true }) else { issue("Cannot read \(root.path)"); return [] }
        var result: [FileItem] = []
        for case let url as URL in walker {
            if cancelled() { break }
            do {
                let v = try url.resourceValues(forKeys: Set(keys))
                guard v.isRegularFile == true, v.isSymbolicLink != true, v.isUbiquitousItem != true else { continue }
                result.append(FileItem(url: url, bytes: Int64(v.fileSize ?? 0), modified: v.contentModificationDate ?? .distantPast))
            } catch { issue("\(url.path): \(error.localizedDescription)") }
        }
        return result
    }
    public static func digest(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    public static func duplicates(_ files: [FileItem], cancelled: () -> Bool = { false }, issue: @escaping (String) -> Void = { _ in }) -> [FileItem] {
        var result: [FileItem] = []
        for candidates in Dictionary(grouping: files.filter { $0.bytes > 0 }, by: \.bytes).values where candidates.count > 1 {
            var hashes: [String: [FileItem]] = [:]
            var identities = Set<String>()
            for item in candidates {
                if cancelled() { return result }
                do {
                    let attrs = try FileManager.default.attributesOfItem(atPath: item.url.path)
                    let identity = "\(attrs[.systemNumber] ?? ""):\(attrs[.systemFileNumber] ?? "")"
                    guard identities.insert(identity).inserted else { continue }
                    let hash = try digest(item.url)
                    hashes[hash, default: []].append(FileItem(url: item.url, bytes: item.bytes, modified: item.modified, group: hash))
                } catch { issue(error.localizedDescription) }
            }
            result += hashes.values.filter { $0.count > 1 }.flatMap { $0 }
        }
        return result.sorted { $0.group == $1.group ? $0.url.path < $1.url.path : $0.group < $1.group }
    }
    public static func applications() throws -> [FileItem] {
        let fm = FileManager.default
        return try fm.contentsOfDirectory(at: URL(fileURLWithPath: "/Applications"), includingPropertiesForKeys: nil).filter { $0.pathExtension == "app" }.map { url in
            FileItem(url: url, bytes: files(in: url).reduce(0) { $0 + $1.bytes })
        }.sorted { $0.bytes > $1.bytes }
    }
    public static func category(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "gif", "svg": return "Images"
        case "mov", "mp4", "mkv", "avi": return "Videos"
        case "mp3", "m4a", "wav", "flac": return "Audio"
        case "zip", "dmg", "pkg", "gz", "tar": return "Archives"
        case "pdf", "docx", "txt", "pages", "xlsx": return "Documents"
        default: return "Other"
        }
    }
}

public struct HistoryEntry: Codable, Identifiable {
    public var id = UUID()
    public let date: Date
    public let action: String
    public let source: String
    public let destination: String
    public let bytes: Int64
}
public final class FileActions {
    private let fm = FileManager.default
    public let historyURL: URL
    public init(historyURL: URL? = nil) {
        self.historyURL = historyURL ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/PurgeOS/history.json")
    }
    public func history() throws -> [HistoryEntry] {
        guard fm.fileExists(atPath: historyURL.path) else { return [] }
        return try JSONDecoder().decode([HistoryEntry].self, from: Data(contentsOf: historyURL))
    }
    private func record(_ entry: HistoryEntry) throws {
        var entries = try history(); entries.insert(entry, at: 0)
        try fm.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: historyURL, options: .atomic)
    }
    public func trash(_ item: FileItem) throws {
        guard FileSafety.allowed(item.url) else { throw CocoaError(.fileWriteNoPermission) }
        let values = try item.url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
        let app = item.url.deletingLastPathComponent().path == "/Applications" && item.url.pathExtension == "app" && values.isDirectory == true
        guard app || values.isRegularFile == true else { throw CocoaError(.fileWriteNoPermission) }
        if !app && (Int64(values.fileSize ?? -1) != item.bytes || values.contentModificationDate != item.modified) {
            throw NSError(domain: "PurgeOS", code: 1, userInfo: [NSLocalizedDescriptionKey: "File changed since scanning. Scan again before cleaning."])
        }
        // Verify history is writable before moving user data.
        try fm.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try history()
        var destination: NSURL?
        try fm.trashItem(at: item.url, resultingItemURL: &destination)
        try record(HistoryEntry(date: Date(), action: "Trash", source: item.url.path, destination: destination?.path ?? "Trash", bytes: item.bytes))
    }
    public func organize(_ item: FileItem, downloads: URL) throws {
        guard item.url.deletingLastPathComponent().standardizedFileURL == downloads.standardizedFileURL,
              FileSafety.allowed(item.url), (try item.url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else { throw CocoaError(.fileWriteNoPermission) }
        let folder = downloads.appendingPathComponent(Scanner.category(item.url))
        guard folder.standardizedFileURL == folder.resolvingSymlinksInPath() else { throw CocoaError(.fileWriteNoPermission) }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(item.url.lastPathComponent)
        guard !fm.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
        _ = try history()
        try fm.moveItem(at: item.url, to: destination)
        try record(HistoryEntry(date: Date(), action: "Organize", source: item.url.path, destination: destination.path, bytes: item.bytes))
    }
}
