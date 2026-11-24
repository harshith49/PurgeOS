import Foundation
import Darwin
import IOKit
import IOKit.ps

public struct SystemSample: Identifiable, Sendable {
    public let id = UUID()
    public let date = Date()
    public let cpu: Double?
    public let usedRAM: UInt64?
    public let totalRAM: UInt64
    public let diskTotal: Int64?
    public let diskFree: Int64?
    public let battery: Double?
    public let batteryHealth: Double?
    public let cycles: Int?
    public let charging: Bool?
}
public final class SystemMonitor {
    private var previous: [UInt64]?
    public init() {}
    public func sample() -> SystemSample {
        var cpuInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let cpuResult = withUnsafeMutablePointer(to: &cpuInfo) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        var cpu: Double?
        if cpuResult == KERN_SUCCESS {
            let ticks = [cpuInfo.cpu_ticks.0, cpuInfo.cpu_ticks.1, cpuInfo.cpu_ticks.2, cpuInfo.cpu_ticks.3].map(UInt64.init)
            if let old = previous {
                let delta = zip(ticks, old).map { $0 &- $1 }; let total = delta.reduce(0, +)
                if total > 0 { cpu = Double(total - delta[2]) / Double(total) * 100 }
            }
            previous = ticks
        }
        var vm = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let vmResult = withUnsafeMutablePointer(to: &vm) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount) }
        }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let ram = vmResult == KERN_SUCCESS ? (UInt64(vm.active_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)) * UInt64(pageSize) : nil
        let disk = try? FileManager.default.homeDirectoryForCurrentUser.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        var battery: Double?, charging: Bool?, health: Double?, cycles: Int?
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                if let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                   let current = d[kIOPSCurrentCapacityKey] as? Double, let max = d[kIOPSMaxCapacityKey] as? Double, max > 0 {
                    battery = current / max * 100; charging = d[kIOPSIsChargingKey] as? Bool
                }
            }
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            func number(_ key: String) -> Double? { (IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.doubleValue }
            if let max = number("AppleRawMaxCapacity") ?? number("MaxCapacity"), let design = number("DesignCapacity"), design > 0, max > 100 { health = max / design * 100 }
            cycles = number("CycleCount").map(Int.init)
        }
        return SystemSample(cpu: cpu, usedRAM: ram, totalRAM: ProcessInfo.processInfo.physicalMemory, diskTotal: disk?.volumeTotalCapacity.map(Int64.init), diskFree: disk?.volumeAvailableCapacity.map(Int64.init), battery: battery, batteryHealth: health, cycles: cycles, charging: charging)
    }
}
