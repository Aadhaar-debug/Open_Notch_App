import Darwin
import Foundation
import IOKit
import IOKit.ps

/// CPU, memory, GPU, network, disk and battery figures, read from public Mach / IOKit /
/// sysctl interfaces (no helper, no root). Sampling runs once a second **only while the
/// Stats tab is on screen**; otherwise this costs nothing.
final class SystemStats: ObservableObject {
    struct Snapshot {
        var cpu: Double = 0              // 0…1
        var cpuUser: Double = 0
        var cpuSystem: Double = 0
        var memoryUsed: UInt64 = 0
        var memoryTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
        var swapUsed: UInt64 = 0
        var gpu: Double?                 // 0…1, nil if the GPU doesn't report it
        var gpuMemory: UInt64?
        var netDown: Double = 0          // bytes / s
        var netUp: Double = 0
        var diskTotal: Int64 = 0
        var diskFree: Int64 = 0
        var battery: Int?
        var charging = false
        var uptime: TimeInterval = 0
        var load: Double = 0
        var thermal: ProcessInfo.ThermalState = .nominal

        var memory: Double { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0 }
        var disk: Double { diskTotal > 0 ? Double(diskTotal - diskFree) / Double(diskTotal) : 0 }
    }

    @Published private(set) var now = Snapshot()
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var gpuHistory: [Double] = []
    @Published private(set) var downHistory: [Double] = []
    @Published private(set) var upHistory: [Double] = []

    private let historyLength = 60
    private var timer: Timer?
    private var viewers = 0
    private var lastCPU: host_cpu_load_info?
    private var lastNet: (down: UInt64, up: UInt64, time: TimeInterval)?
    private var lastDiskRead = Date.distantPast

    // MARK: Lifecycle (reference counted by visible views)

    func resume() {
        viewers += 1
        guard timer == nil else { return }
        sample()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.sample() }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func pause() {
        viewers = max(viewers - 1, 0)
        guard viewers == 0 else { return }
        timer?.invalidate()
        timer = nil
        // Rates need two samples; start fresh next time instead of averaging over the pause.
        lastCPU = nil
        lastNet = nil
    }

    // MARK: Sampling

    func sample() {
        var s = now
        readCPU(into: &s)
        readMemory(into: &s)
        (s.gpu, s.gpuMemory) = Self.readGPU()
        readNetwork(into: &s)
        if Date().timeIntervalSince(lastDiskRead) > 10 { readDisk(into: &s); lastDiskRead = Date() }
        readBattery(into: &s)
        s.uptime = ProcessInfo.processInfo.systemUptime
        var loads = [Double](repeating: 0, count: 3)
        if getloadavg(&loads, 3) > 0 { s.load = loads[0] }
        s.thermal = ProcessInfo.processInfo.thermalState
        now = s

        push(&cpuHistory, s.cpu)
        push(&gpuHistory, s.gpu ?? 0)
        push(&downHistory, s.netDown)
        push(&upHistory, s.netUp)
    }

    private func push(_ history: inout [Double], _ value: Double) {
        history.append(value)
        if history.count > historyLength { history.removeFirst(history.count - historyLength) }
    }

    private func readCPU(into s: inout Snapshot) {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        defer { lastCPU = info }
        guard let last = lastCPU else { return }
        func delta(_ a: natural_t, _ b: natural_t) -> Double { Double(a &- b) }
        let user = delta(info.cpu_ticks.0, last.cpu_ticks.0) + delta(info.cpu_ticks.3, last.cpu_ticks.3) // user + nice
        let system = delta(info.cpu_ticks.1, last.cpu_ticks.1)
        let idle = delta(info.cpu_ticks.2, last.cpu_ticks.2)
        let total = user + system + idle
        guard total > 0 else { return }
        s.cpuUser = user / total
        s.cpuSystem = system / total
        s.cpu = (user + system) / total
    }

    /// "Memory Used" the way Activity Monitor counts it: app memory + wired + compressed.
    private func readMemory(into s: inout Snapshot) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            let page = UInt64(vm_kernel_page_size)
            let app = UInt64(stats.internal_page_count) &- UInt64(stats.purgeable_count)
            s.memoryUsed = (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        }
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 { s.swapUsed = swap.xsu_used }
    }

    /// GPU busy % from the IOAccelerator's PerformanceStatistics (Apple silicon, AMD, Intel).
    static func readGPU() -> (Double?, UInt64?) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator)
                == KERN_SUCCESS else { return (nil, nil) }
        defer { IOObjectRelease(iterator) }
        var utilization: Double?
        var memory: UInt64?
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            guard let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString,
                                                              kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any] else { continue }
            if let u = (stats["Device Utilization %"] ?? stats["GPU Activity(%)"]) as? NSNumber {
                utilization = max(utilization ?? 0, u.doubleValue / 100)
            }
            if let m = (stats["In use system memory"] ?? stats["vramUsedBytes"]) as? NSNumber {
                memory = max(memory ?? 0, m.uint64Value)
            }
        }
        return (utilization, memory)
    }

    /// Bytes in/out over physical interfaces (en*, cellular), from 64-bit interface counters.
    /// VPN tunnels (utun) are skipped so their traffic isn't counted twice.
    private func readNetwork(into s: inout Snapshot) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return }

        var down: UInt64 = 0, up: UInt64 = 0
        var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let h2 = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if if_indextoname(UInt32(h2.ifm_index), &name) != nil {
                        let ifName = String(cString: name)
                        if ifName.hasPrefix("en") || ifName.hasPrefix("pdp_ip") {
                            down += h2.ifm_data.ifi_ibytes
                            up += h2.ifm_data.ifi_obytes
                        }
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        let t = ProcessInfo.processInfo.systemUptime
        if let last = lastNet, t > last.time, down >= last.down, up >= last.up {
            s.netDown = Double(down - last.down) / (t - last.time)
            s.netUp = Double(up - last.up) / (t - last.time)
        }
        lastNet = (down, up, t)
    }

    private func readDisk(into s: inout Snapshot) {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) else { return }
        s.diskTotal = Int64(values.volumeTotalCapacity ?? 0)
        s.diskFree = values.volumeAvailableCapacityForImportantUsage ?? 0
    }

    private func readBattery(into s: inout Snapshot) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            s.battery = d[kIOPSCurrentCapacityKey] as? Int
            s.charging = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
        }
    }
}
