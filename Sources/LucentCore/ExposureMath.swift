import Foundation

public struct ExposureLimits: Sendable {
    public let iso: ClosedRange<Double>
    public let duration: ClosedRange<Double>
    public init(iso: ClosedRange<Double>, duration: ClosedRange<Double>) {
        self.iso = iso; self.duration = duration
    }
    public func clampISO(_ value: Double) -> Double { clamp(value, to: iso) }
    public func clampDuration(_ value: Double) -> Double { clamp(value, to: duration) }
    /// A bounded proportional step for priority modes on older OS versions.
    public func priorityAdjustment(current: Double, meterOffset: Double, forISO: Bool) -> Double {
        let correction = pow(2, -clamp(meterOffset, to: -0.5...0.5))
        return forISO ? clampISO(current * correction) : clampDuration(current * correction)
    }
}

public func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
    guard value.isFinite else { return range.lowerBound }
    return min(range.upperBound, max(range.lowerBound, value))
}

public func shutterLabel(_ seconds: Double) -> String {
    guard seconds.isFinite && seconds > 0 else { return "—" }
    if seconds >= 1 { return String(format: "%.1fs", seconds) }
    return "1/\(Int((1 / max(seconds, 0.000000001)).rounded()))"
}

public func logarithmicValue(_ fraction: Double, range: ClosedRange<Double>) -> Double {
    guard range.lowerBound > 0 else { return range.lowerBound }
    return exp(log(range.lowerBound) + clamp(fraction, to: 0...1) * log(range.upperBound / range.lowerBound))
}

public func logarithmicFraction(_ value: Double, range: ClosedRange<Double>) -> Double {
    guard range.lowerBound > 0, range.upperBound > range.lowerBound else { return 0 }
    return log(clamp(value, to: range) / range.lowerBound) / log(range.upperBound / range.lowerBound)
}
