import SwiftUI
import AppKit
import Charts
import PurgeCore

@main struct PurgeOSApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("PurgeOS") { ContentView().environmentObject(model).frame(minWidth: 1000, minHeight: 680).preferredColorScheme(.dark) }
        MenuBarExtra {
            if let s = model.samples.last {
                Text("CPU: \(s.cpu.map { String(format: "%.1f%%", $0) } ?? "Measuring…")")
                Text("Memory: \(s.usedRAM.map { size(Int64($0)) } ?? "Unavailable")")
                Text("Battery: \(s.battery.map { String(format: "%.0f%%", $0) } ?? "Unavailable")")
            }
            Button("Open PurgeOS") { NSApp.activate(ignoringOtherApps: true); NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil) }
            Divider()
            Button("Quit PurgeOS") { NSApp.terminate(nil) }
        } label: { Label("PurgeOS", systemImage: "sparkles") }
    }
}
struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmation = false
    @State private var organize = false
    @State private var hoveredCategory: String?
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 24) {
                Label("PurgeOS", systemImage: "sparkles").font(.title.bold()).foregroundStyle(.purple)
                Text("A LIGHTER MAC.").font(.caption).foregroundStyle(.secondary)
                List(Module.allCases, selection: $model.module) { module in
                    Label(module.rawValue, systemImage: module.icon).tag(module).padding(.vertical, 5)
                }.listStyle(.sidebar)
                Label("Private. Offline. Yours.", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
            }.padding().background(.ultraThinMaterial).navigationSplitViewColumnWidth(min: 240, ideal: 250, max: 300)
        } detail: {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(model.module.rawValue).font(.largeTitle.bold())
                        Text(subtitle).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.busy { ProgressView(); Button("Cancel", action: model.cancel) }
                }
                if model.module == .dashboard { dashboard }
                else if model.module == .history { history }
                else { files }
            }.padding(30).background(LinearGradient(colors: [Color.purple.opacity(0.13), Color.black.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .tint(.purple)
        .onChange(of: model.module) { _ in model.items = []; model.selected = []; model.loadHistory() }
        .alert("Unable to complete every operation", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
        .confirmationDialog(organize ? "Move selected Downloads into category folders?" : "Move \(model.selected.count) selected items to Trash?", isPresented: $confirmation, titleVisibility: .visible) {
            Button(organize ? "Organize selected files" : "Move to Trash", role: organize ? nil : .destructive) { model.perform(organize: organize) }
            Button("Cancel", role: .cancel) {}
        } message: { Text(organize ? "Existing files will never be overwritten." : "Review your selection first. You can restore files from Finder’s Trash. Apps must be closed; their documents and support data are retained.") }
    }
    var subtitle: String {
        switch model.module {
        case .dashboard: return "Your Mac, at a glance. Live readings every two seconds."
        case .junk, .caches: return "Review user caches and logs older than seven days. Quit related apps first."
        case .duplicates: return "SHA-256 content matching. Keep at least one copy per group."
        case .apps: return "Move application bundles to Trash. Support data is retained for safety."
        case .large: return "Files of 100 MB or larger in your chosen folder."
        case .storage: return "Logical file sizes in your chosen folder; APFS disk use may differ."
        case .downloads: return "Select files to move into category folders without overwriting."
        case .history: return "A local record of file moves and cleanup."
        }
    }
    var dashboard: some View {
        ScrollView {
            if let s = model.samples.last {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                    metric("CPU", value: s.cpu.map { String(format: "%.1f%%", $0) } ?? "Measuring…", icon: "cpu")
                    metric("Memory in use", value: s.usedRAM.map { size(Int64($0)) + " / " + size(Int64(s.totalRAM)) } ?? "Unavailable", icon: "memorychip")
                    metric("Disk available", value: s.diskFree.map(size) ?? "Unavailable", icon: "internaldrive")
                    metric("Battery", value: s.battery.map { String(format: "%.0f%%", $0) + (s.charging == true ? " • Charging" : "") } ?? "No battery reported", icon: "battery.100")
                }
                VStack(alignment: .leading) {
                    Text("CPU activity").font(.headline)
                    Chart(model.samples) { sample in
                        if let cpu = sample.cpu { AreaMark(x: .value("Time", sample.date), y: .value("CPU %", cpu)).foregroundStyle(.purple.opacity(0.25)); LineMark(x: .value("Time", sample.date), y: .value("CPU %", cpu)).foregroundStyle(.purple).interpolationMethod(.catmullRom) }
                    }.chartYScale(domain: 0...100).frame(height: 170)
                    Text("Battery health: \(s.batteryHealth.map { String(format: "%.0f%% of design capacity", $0) } ?? "Not reported by this Mac") • Cycles: \(s.cycles.map(String.init) ?? "Unavailable")").font(.caption).foregroundStyle(.secondary)
                    if let total = s.diskTotal, let free = s.diskFree, total > 0 { ProgressView(value: Double(total - free), total: Double(total)); Text("\(size(total - free)) used of \(size(total))").font(.caption) }
                }.padding(22).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22)).padding(.top)
                Button("Scan smart junk") { model.module = .junk; model.scan() }.buttonStyle(.borderedProminent).padding(.top)
            }
        }
    }
    func metric(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 14) { Label(title, systemImage: icon).foregroundStyle(.secondary); Text(value).font(.title2.bold()).contentTransition(.numericText()) }.frame(maxWidth: .infinity, alignment: .leading).padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22)).animation(.easeInOut, value: value)
    }
    var files: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                if [.duplicates, .large, .storage].contains(model.module) { Button("Choose folder…", action: model.chooseFolder).disabled(model.busy); Text(model.root.path).lineLimit(1).truncationMode(.middle).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Scan", action: model.scan).buttonStyle(.borderedProminent).disabled(model.busy)
            }
            if model.module == .storage && !model.items.isEmpty { storageChart }
            Table(model.items, selection: $model.selected) {
                TableColumn("Name") { item in
                    VStack(alignment: .leading) { Text(item.url.lastPathComponent); Text(item.url.deletingLastPathComponent().path).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                    .contextMenu { Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } }
                }
                TableColumn("Size") { Text(size($0.bytes)) }.width(100)
                TableColumn(model.module == .duplicates ? "Content group" : "Kind") { item in Text(model.module == .duplicates ? String(item.group.prefix(10)) : Scanner.category(item.url)).font(.caption) }.width(110)
            }
            HStack {
                Text(model.status).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(model.selected.count) selected").font(.caption)
                if model.module == .downloads { Button("Organize…") { organize = true; confirmation = true }.disabled(model.selected.isEmpty || model.busy) }
                Button("Trash selected…", role: .destructive) { organize = false; confirmation = true }.disabled(model.selected.isEmpty || model.busy)
            }
        }
    }
    var storageChart: some View {
        let groups = Dictionary(grouping: model.items, by: { Scanner.category($0.url) }).map { (name: $0.key, bytes: $0.value.reduce(Int64(0)) { $0 + $1.bytes }) }.sorted { $0.bytes > $1.bytes }
        return Chart(groups, id: \.name) { group in
            BarMark(x: .value("Size", group.bytes), y: .value("Category", group.name)).foregroundStyle(.purple.gradient)
        }.chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle()).onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let y = location.y - geometry[proxy.plotAreaFrame].origin.y
                        hoveredCategory = proxy.value(atY: y, as: String.self)
                    case .ended: hoveredCategory = nil
                    }
                }
            }
        }.overlay(alignment: .topTrailing) {
            if let group = groups.first(where: { $0.name == hoveredCategory }) {
                Text("\(group.name): \(size(group.bytes))").font(.caption).padding(8).background(.ultraThinMaterial, in: Capsule())
            }
        }.chartXAxis { AxisMarks { value in AxisValueLabel { if let bytes = value.as(Int64.self) { Text(size(bytes)) } } } }.frame(height: 180)
    }
    var history: some View {
        List(model.history) { entry in
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text(entry.action).font(.headline); Spacer(); Text(entry.date, style: .date); Text(size(entry.bytes)) }
                Text(entry.source).font(.caption).textSelection(.enabled)
                Text("→ " + entry.destination).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }.padding(.vertical, 8)
        }.overlay { if model.history.isEmpty { Text("Your cleanup history will appear here.").foregroundStyle(.secondary) } }
    }
}
