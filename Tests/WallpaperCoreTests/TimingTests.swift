import Foundation
import Testing
@testable import WallpaperCore

@Suite("Animation timing")
struct TimingTests {
    @Test func firstTimestampOnlyPrimesTheClock() {
        var c = AnimationClock()
        #expect(c.advance(to: 100, speed: 1) == 0)
        #expect(c.phase == 0)
        #expect(c.advance(to: 100.125, speed: 1) == 0.125)
        #expect(c.phase == 0.125)
    }

    @Test func olderOrEqualTimestampsAreIgnored() {
        // Two displays driving one clock: the slower link reports older timestamps.
        var c = AnimationClock()
        c.advance(to: 10, speed: 1)
        c.advance(to: 10.1, speed: 1)
        #expect(c.advance(to: 10.05, speed: 1) == 0)
        #expect(c.advance(to: 10.1, speed: 1) == 0)
        #expect(abs(c.phase - 0.1) < 1e-12)
    }

    @Test func largeGapsAreClamped() {
        var c = AnimationClock()
        c.advance(to: 0, speed: 1)
        #expect(c.advance(to: 3600, speed: 1) == AnimationClock.maxStep)  // e.g. after sleep
        #expect(c.phase == AnimationClock.maxStep)
    }

    @Test func speedScalesPhaseWithoutJumps() {
        var c = AnimationClock()
        c.advance(to: 0, speed: 1)
        c.advance(to: 0.1, speed: 1)
        let before = c.phase
        c.advance(to: 0.2, speed: 4)              // speed change applies to the new interval only
        #expect(abs(c.phase - (before + 0.4)) < 1e-12)
        c.advance(to: 0.3, speed: 0)
        #expect(abs(c.phase - (before + 0.4)) < 1e-12)
    }

    @Test(arguments: [-1000.0, -0.5, 0, 255.9, 256, 1e9 + 0.25])
    func wrapStaysInRange(x: Double) {
        let w = AnimationClock.wrap(x)
        #expect(w >= 0 && w < Double(AnimationClock.period))
    }

    @Test func offsetsStayInRangeAfterWeeksOfUptime() {
        var c = AnimationClock(phase: 60 * 60 * 24 * 30)   // 30 days at speed 1
        c.setPhase(c.phase + 0.123)
        let (a, b, d) = c.packedOffsets
        for v in [a, b, d] {
            for i in 0..<4 { #expect(v[i] >= 0 && v[i] < Float(AnimationClock.period)) }
        }
    }

    @Test func nextWrapPhaseIsAWrapBoundary() {
        for component in 0..<12 {
            let p = AnimationClock.nextWrapPhase(component: component, after: 100)
            #expect(p > 100)
            let v = AnimationClock.velocities[component / 2]
            let speed = abs(component % 2 == 0 ? v.x : v.y)
            let cycles = p * speed / Double(AnimationClock.period)
            #expect(abs(cycles - cycles.rounded()) < 1e-9)
        }
    }

    @Test func smoothingIsFrameRateIndependent() {
        func settle(fps: Double, seconds: Double) -> Double {
            var value = 0.0
            let dt = 1 / fps
            for _ in 0..<Int(seconds * fps) {
                value += (1 - value) * Smoothing.factor(dt: dt, timeConstant: 0.6)
            }
            return value
        }
        let at15 = settle(fps: 15, seconds: 1)
        let at60 = settle(fps: 60, seconds: 1)
        #expect(abs(at15 - at60) < 1e-9)
        #expect(abs(at60 - (1 - exp(-1 / 0.6))) < 1e-9)
    }

    @Test func paletteTransitionCompletesAfterDuration() {
        var t = PaletteTransition(palette: .aurora, duration: 2)
        #expect(!t.isActive)
        t.begin(to: .ember)
        #expect(t.isActive && t.easedProgress == 0)
        t.advance(by: 1)
        #expect(t.isActive && abs(t.easedProgress - 0.5) < 1e-12)
        t.advance(by: 1.5)
        #expect(!t.isActive)
        #expect(t.currentRamp() == Palette.ember.ramp(count: PaletteTransition.rampSize))
    }

    @Test func interruptingATransitionStartsFromTheVisibleBlend() {
        var t = PaletteTransition(palette: .aurora, duration: 2)
        t.begin(to: .ember)
        t.advance(by: 0.7)
        let visible = t.currentRamp()
        t.begin(to: .ocean)
        #expect(t.currentRamp() == visible)     // no jump at the moment of interruption
        #expect(t.to == Palette.ocean.ramp(count: PaletteTransition.rampSize))
    }

    @Test func zeroDurationSwitchesInstantly() {
        var t = PaletteTransition(palette: .aurora, duration: 0)
        t.begin(to: .forest)
        #expect(!t.isActive)
        #expect(t.currentRamp() == Palette.forest.ramp(count: PaletteTransition.rampSize))
    }
}
