import Darwin
import Foundation

/// Process-level measurements from public APIs.
///
/// - CPU: `getrusage(RUSAGE_SELF)` user+system time delta over wall-time delta. Measured.
///   100 % = one core fully busy.
/// - Memory: `phys_footprint` from `proc_pid_rusage`, the same number Activity Monitor
///   shows as "Memory". Measured. It includes IOSurface/GPU memory attributed to this
///   process, which covers Metal drawables and textures.
/// - GPU utilisation: no public API reports it per process, so it is not reported.
public struct ProcessMetrics: Sendable {
    public struct Sample: Sendable {
        public var cpuPercent: Double?
        public var footprintBytes: UInt64?
    }

    private var lastCPU: Double?
    private var lastWall: Double?

    public init() {}

    public mutating func sample() -> Sample {
        let wall = ProcessInfo.processInfo.systemUptime
        let cpu = Self.cpuSeconds()
        var percent: Double?
        if let lastCPU, let lastWall, wall > lastWall {
            percent = (cpu - lastCPU) / (wall - lastWall) * 100
        }
        lastCPU = cpu
        lastWall = wall
        return Sample(cpuPercent: percent, footprintBytes: Self.footprint())
    }

    static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func s(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return s(usage.ru_utime) + s(usage.ru_stime)
    }

    /// Lifetime peak `phys_footprint` of this process (measured).
    public static func peakFootprint() -> UInt64? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? info.ri_lifetime_max_phys_footprint : nil
    }

    static func footprint() -> UInt64? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? info.ri_phys_footprint : nil
    }
}
