import Foundation

/// Per-display frame counters. Written from the main thread (CPU encode time) and from
/// Metal's completion handler thread (GPU time), so access is lock-protected.
public final class FrameStats: @unchecked Sendable {
    public struct Window: Sendable {
        public var seconds: Double
        public var frames: Int
        /// Mean wall time between `gpuStartTime` and `gpuEndTime` per command buffer. This is
        /// NOT GPU utilisation: it includes GPU clock-state effects. Relative indicator only.
        public var gpuWallMs: Double
        /// Mean CPU time spent encoding a frame on the main thread.
        public var cpuEncodeMs: Double
        public var measuredFPS: Double { seconds > 0 ? Double(frames) / seconds : 0 }
        /// Mean CPU-side interval between presented frames.
        public var frameIntervalMs: Double { frames > 0 ? seconds / Double(frames) * 1000 : 0 }
    }

    private let lock = NSLock()
    private var frames = 0
    private var gpuSeconds: Double = 0
    private var gpuSamples = 0
    private var cpuSeconds: Double = 0
    private var windowStart = ProcessInfo.processInfo.systemUptime

    public init() {}

    public func recordFrame(cpuEncode: Double) {
        lock.lock(); frames += 1; cpuSeconds += cpuEncode; lock.unlock()
    }

    public func recordGPU(_ seconds: Double) {
        guard seconds > 0 else { return }
        lock.lock(); gpuSeconds += seconds; gpuSamples += 1; lock.unlock()
    }

    /// Returns the stats since the previous call and starts a new window.
    public func drain() -> Window {
        lock.lock()
        defer { lock.unlock() }
        let now = ProcessInfo.processInfo.systemUptime
        let w = Window(seconds: now - windowStart, frames: frames,
                       gpuWallMs: gpuSamples > 0 ? gpuSeconds / Double(gpuSamples) * 1000 : 0,
                       cpuEncodeMs: frames > 0 ? cpuSeconds / Double(frames) * 1000 : 0)
        frames = 0; gpuSeconds = 0; gpuSamples = 0; cpuSeconds = 0; windowStart = now
        return w
    }
}
