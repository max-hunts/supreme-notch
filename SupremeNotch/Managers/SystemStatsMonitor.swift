//
//  SystemStatsMonitor.swift
//  SupremeNotch
//
//  CPU, memory and startup disk use, plus network throughput over the last five minutes.
//  Mach host statistics, volume capacity and getifaddrs need no permission. CPU, memory
//  and disk are read only while the System tab is on screen; network byte counters are
//  read every 5 seconds in the background so the chart has history when you open it.
//

import Combine
import Darwin
import Foundation

nonisolated struct NetworkSample: Equatable {
    let at: Date
    let downBytesPerSecond: Double
    let upBytesPerSecond: Double
}

nonisolated struct SystemStats: Equatable {
    var cpuPercent: Double = 0
    var memoryUsedBytes: UInt64 = 0
    var memoryTotalBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    var diskUsedBytes: UInt64 = 0
    var diskTotalBytes: UInt64 = 0
}

@MainActor
final class SystemStatsMonitor: ObservableObject {
    @Published private(set) var stats = SystemStats()
    /// One sample every 5 seconds, oldest first, covering the last five minutes.
    @Published private(set) var networkHistory: [NetworkSample] = []

    static let networkWindow: TimeInterval = 5 * 60
    private static let networkInterval: Duration = .seconds(5)
    private var networkTask: Task<Void, Never>?
    private var previousNetwork: (received: UInt64, sent: UInt64, at: Date)?

    private var liveTask: Task<Void, Never>?
    private var liveCount = 0
    private var previousTicks: (used: UInt64, total: UInt64)?

    /// Starts the background network sampler. Cheap: two counters every 5 seconds.
    func start() {
        guard networkTask == nil else { return }
        networkTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.sampleNetwork()
                try? await Task.sleep(for: Self.networkInterval)
            }
        }
    }

    func stop() {
        networkTask?.cancel()
        networkTask = nil
    }

    private func sampleNetwork() {
        guard let counters = Self.networkBytes() else { return }
        let now = Date()
        defer { previousNetwork = (counters.received, counters.sent, now) }
        guard let previous = previousNetwork else { return }

        let seconds = max(1, now.timeIntervalSince(previous.at))
        // Counters reset when an interface goes away; skip that sample rather than spike.
        guard counters.received >= previous.received, counters.sent >= previous.sent else { return }
        let sample = NetworkSample(
            at: now,
            downBytesPerSecond: Double(counters.received - previous.received) / seconds,
            upBytesPerSecond: Double(counters.sent - previous.sent) / seconds
        )
        var history = networkHistory.filter { now.timeIntervalSince($0.at) <= Self.networkWindow }
        history.append(sample)
        networkHistory = history
    }

    func startLive() {
        liveCount += 1
        guard liveTask == nil else { return }
        liveTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stopLive() {
        liveCount = max(0, liveCount - 1)
        guard liveCount == 0 else { return }
        liveTask?.cancel()
        liveTask = nil
        previousTicks = nil
    }

    private func sample() {
        var next = stats

        if let ticks = Self.cpuTicks() {
            if let previous = previousTicks, ticks.total > previous.total {
                next.cpuPercent = Double(ticks.used - previous.used) / Double(ticks.total - previous.total) * 100
            }
            previousTicks = ticks
        }

        next.memoryUsedBytes = Self.memoryUsed() ?? next.memoryUsedBytes

        if let disk = Self.diskUsage() {
            next.diskUsedBytes = disk.used
            next.diskTotalBytes = disk.total
        }

        if next != stats {
            stats = next
        }
    }

    // MARK: - Sources

    nonisolated private static func cpuTicks() -> (used: UInt64, total: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        return (user + system + nice, user + system + idle + nice)
    }

    /// Memory in use the way Activity Monitor counts it: app, wired and compressed pages.
    nonisolated private static func memoryUsed() -> UInt64? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pageSize = UInt64(vm_kernel_page_size)
        let appPages = UInt64(info.internal_page_count) - UInt64(info.purgeable_count)
        return (appPages + UInt64(info.wire_count) + UInt64(info.compressor_page_count)) * pageSize
    }

    /// Startup disk use, counting space macOS can free (purgeable) as available, like Finder.
    nonisolated private static func diskUsage() -> (used: UInt64, total: UInt64)? {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else { return nil }
        let totalBytes = UInt64(max(0, total))
        let availableBytes = UInt64(max(0, available))
        return (totalBytes > availableBytes ? totalBytes - availableBytes : 0, totalBytes)
    }

    nonisolated private static func networkBytes() -> (received: UInt64, sent: UInt64)? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return nil }
        defer { freeifaddrs(pointer) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let data = entry.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            received += UInt64(data.pointee.ifi_ibytes)
            sent += UInt64(data.pointee.ifi_obytes)
        }
        return (received, sent)
    }

    #if DEBUG
    /// Sample data for README images.
    func previewLoad(stats: SystemStats, history: [NetworkSample]) {
        self.stats = stats
        networkHistory = history
    }
    #endif
}
