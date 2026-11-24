import SwiftUI
import AppKit
import PurgeCore

enum Module: String, CaseIterable, Identifiable {
    case dashboard = "Overview", junk = "Smart Junk", caches = "Cache Cleaner", duplicates = "Duplicates", large = "Large Files", apps = "Uninstaller", storage = "Storage", downloads = "Downloads", history = "History"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .junk: return "sparkles"
        case .caches: return "externaldrive.badge.minus"
        case .duplicates: return "doc.on.doc"
        case .large: return "doc.zipper"
        case .apps: return "app.badge"
        case .storage: return "chart.pie"
        case .downloads: return "arrow.down.circle"
        case .history: return "clock.arrow.circlepath"
        }
    }
}
@MainActor final class AppModel: ObservableObject {
    @Published var module: Module = .dashboard
    @Published var root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    @Published var items: [FileItem] = []
    @Published var selected = Set<String>()
    @Published var samples: [SystemSample] = []
    @Published var busy = false
    @Published var status = "Choose a module to begin. Nothing is selected automatically."
    @Published var error: String?
    @Published var history: [HistoryEntry] = []
    private let monitor = SystemMonitor()
    let actions = FileActions()
    private var timer: Timer?
    private var work: Task<Void, Never>?
    init() {
        tick(); loadHistory()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }
    func tick() { samples.append(monitor.sample()); if samples.count > 60 { samples.removeFirst() } }
    func loadHistory() { do { history = try actions.history() } catch { self.error = error.localizedDescription } }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { root = url; items = []; selected = [] }
    }
    func scan() {
        guard !busy else { return }
        busy = true; items = []; selected = []; status = "Scanning… inaccessible and cloud-only files are skipped."
        let mode = module, folder = root
        work = Task {
            let worker = Task.detached(priority: .userInitiated) { () -> ([FileItem], [String]) in
                var issues: [String] = []
                let report: (String) -> Void = { if issues.count < 20 { issues.append($0) } }
                let stop = { Task.isCancelled }
                let fm = FileManager.default
                let home = fm.homeDirectoryForCurrentUser
                var files: [FileItem]
                switch mode {
                case .junk, .caches:
                    let roots = mode == .caches ? ["Library/Caches"] : ["Library/Caches", "Library/Logs"]
                    files = roots.flatMap { Scanner.files(in: home.appendingPathComponent($0), cancelled: stop, issue: report) }
                    let cutoff = Date().addingTimeInterval(-7 * 86400)
                    files = files.filter { $0.modified < cutoff && FileSafety.allowed($0.url) }
                case .apps:
                    do { files = try Scanner.applications() } catch { report(error.localizedDescription); files = [] }
                case .downloads:
                    let downloads = home.appendingPathComponent("Downloads")
                    files = Scanner.files(in: downloads, cancelled: stop, issue: report).filter { $0.url.deletingLastPathComponent() == downloads }
                default:
                    files = Scanner.files(in: folder, cancelled: stop, issue: report)
                    if mode == .duplicates { files = Scanner.duplicates(files, cancelled: stop, issue: report) }
                    if mode == .large { files = files.filter { $0.bytes >= 100 * 1024 * 1024 } }
                }
                if mode != .duplicates { files.sort { $0.bytes > $1.bytes } }
                return (files, issues)
            }
            let result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
            if !Task.isCancelled && module == mode {
                items = result.0
                status = "\(items.count) files • \(size(items.reduce(0) { $0 + $1.bytes })) scanned" + (result.1.isEmpty ? "" : " • Some paths could not be read")
                if !result.1.isEmpty { error = result.1.joined(separator: "\n") }
            }
            busy = false
        }
    }
    func cancel() { work?.cancel(); status = "Cancelling; waiting for current file read to finish." }
    func perform(organize: Bool) {
        let chosen = items.filter { selected.contains($0.id) }
        if module == .duplicates && !organize {
            let groups = Dictionary(grouping: items, by: \.group)
            if groups.values.contains(where: { group in
                guard group.contains(where: { selected.contains($0.id) }) else { return false }
                return !group.contains { !selected.contains($0.id) && FileManager.default.fileExists(atPath: $0.url.path) }
            }) {
                error = "Keep at least one file in every duplicate group."; return
            }
        }
        var failures: [String] = [], completed = Set<String>()
        for item in chosen {
            do {
                if organize { try actions.organize(item, downloads: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")) }
                else {
                    if item.url.pathExtension == "app", NSWorkspace.shared.runningApplications.contains(where: { $0.bundleURL == item.url }) { throw CocoaError(.fileWriteNoPermission) }
                    try actions.trash(item)
                }
                completed.insert(item.id)
            } catch { failures.append("\(item.url.lastPathComponent): \(error.localizedDescription)") }
        }
        items.removeAll { completed.contains($0.id) }; selected.subtract(completed); loadHistory()
        status = "\(completed.count) items \(organize ? "organized" : "moved to Trash")."
        if !failures.isEmpty { error = failures.joined(separator: "\n") }
    }
}
func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
