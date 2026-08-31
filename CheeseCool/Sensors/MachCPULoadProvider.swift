import Darwin
import Foundation

public struct CPUTickSnapshot: Equatable, Sendable {
    public let user: UInt64
    public let system: UInt64
    public let nice: UInt64
    public let idle: UInt64

    public init(user: UInt64, system: UInt64, nice: UInt64, idle: UInt64) {
        self.user = user
        self.system = system
        self.nice = nice
        self.idle = idle
    }
}

public protocol CPUTickSource: Sendable {
    func readTicks() throws -> CPUTickSnapshot
}

public struct MachHostCPUTickSource: CPUTickSource {
    public init() {}

    public func readTicks() throws -> CPUTickSnapshot {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            throw SensorError.failed("host_statistics failed: \(result)")
        }
        return CPUTickSnapshot(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            nice: UInt64(info.cpu_ticks.3),
            idle: UInt64(info.cpu_ticks.2)
        )
    }
}

public actor MachCPULoadProvider: CPULoadProviding {
    private let source: any CPUTickSource
    private var previous: CPUTickSnapshot?

    public init(source: any CPUTickSource = MachHostCPUTickSource()) {
        self.source = source
    }

    public func readCPULoad(now: TimeInterval) -> MetricSample {
        let started = ContinuousClock.now
        do {
            let current = try source.readTicks()
            defer { previous = current }
            guard let previous else {
                return unavailable(now: now, reason: "Waiting for the second cumulative tick sample", started: started)
            }
            guard current.user >= previous.user,
                  current.system >= previous.system,
                  current.nice >= previous.nice,
                  current.idle >= previous.idle else {
                return unavailable(now: now, reason: "Cumulative CPU counters reset", started: started)
            }
            let busy = (current.user - previous.user)
                + (current.system - previous.system)
                + (current.nice - previous.nice)
            let idle = current.idle - previous.idle
            let total = busy + idle
            guard total > 0 else {
                return unavailable(now: now, reason: "CPU counters did not advance", started: started)
            }
            let value = min(100, max(0, Double(busy) / Double(total) * 100))
            return .valid(
                value,
                timestamp: now,
                source: "Mach HOST_CPU_LOAD_INFO delta",
                latencyMilliseconds: Self.milliseconds(started.duration(to: .now))
            )
        } catch {
            return unavailable(now: now, reason: error.localizedDescription, started: started)
        }
    }

    private func unavailable(
        now: TimeInterval,
        reason: String,
        started: ContinuousClock.Instant
    ) -> MetricSample {
        .unavailable(
            timestamp: now,
            source: "Mach HOST_CPU_LOAD_INFO delta",
            reason: reason,
            latencyMilliseconds: Self.milliseconds(started.duration(to: .now))
        )
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
