import Foundation

public enum AutoDecisionReason: String, Codable, Sendable {
    case curve = "CURVE"
    case dutyDeadband = "DUTY_DEADBAND"
    case rampUpLimit = "RAMP_UP_LIMIT"
    case rampDownLimit = "RAMP_DOWN_LIMIT"
    case criticalOverride = "CRITICAL_OVERRIDE"
    case temperatureGraceHold = "HOST_TEMPERATURE_GRACE_HOLD"
    case temperatureUnavailable = "HOST_TEMPERATURE_UNAVAILABLE"
}

public struct AutoControlDecision: Codable, Equatable, Sendable {
    public let timestamp: TimeInterval
    public let valid: Bool
    public let requestedDuty: Double?
    public let reason: AutoDecisionReason
    public let temperatureCelsius: Double?
    public let temperatureState: TemperatureState
    public let rawCurveDuty: Double?
}

public struct AutoController: Sendable {
    public let configuration: Configuration
    private var lastRequestedDuty: Double?
    private var lastUpdateTime: TimeInterval?
    private var lastValidTime: TimeInterval?

    public init(configuration: Configuration = .defaults) {
        self.configuration = configuration
    }

    public static func interpolate(
        temperatureCelsius: Double,
        curve: [AutoCurvePoint] = Configuration.defaults.autoCurve
    ) -> Double {
        guard let first = curve.first, let last = curve.last else { return 0 }
        if temperatureCelsius <= first.temperatureCelsius { return first.duty }
        if temperatureCelsius >= last.temperatureCelsius { return last.duty }

        for (low, high) in zip(curve, curve.dropFirst()) {
            if temperatureCelsius >= low.temperatureCelsius,
               temperatureCelsius <= high.temperatureCelsius {
                let fraction = (temperatureCelsius - low.temperatureCelsius)
                    / (high.temperatureCelsius - low.temperatureCelsius)
                return low.duty + fraction * (high.duty - low.duty)
            }
        }
        preconditionFailure("AUTO curve has a gap")
    }

    public mutating func update(sample: TemperatureSample, now: TimeInterval) -> AutoControlDecision {
        guard isUsable(sample: sample, now: now),
              let temperature = sample.controlTemperatureCelsius else {
            return invalidDecision(now: now)
        }

        let rawDuty = Self.interpolate(
            temperatureCelsius: temperature,
            curve: configuration.autoCurve
        ).clamped(to: 0...100)
        let requested: Double
        let reason: AutoDecisionReason

        if sample.state == .critical {
            requested = 100
            reason = .criticalOverride
        } else if let previous = lastRequestedDuty {
            let delta = rawDuty - previous
            if abs(delta) < configuration.deadband {
                requested = previous
                reason = .dutyDeadband
            } else {
                let elapsed = max(0, now - (lastUpdateTime ?? now))
                if delta > 0 {
                    requested = min(rawDuty, previous + configuration.rampUpPerSecond * elapsed)
                    reason = requested < rawDuty ? .rampUpLimit : .curve
                } else {
                    requested = max(rawDuty, previous - configuration.rampDownPerSecond * elapsed)
                    reason = requested > rawDuty ? .rampDownLimit : .curve
                }
            }
        } else {
            requested = rawDuty
            reason = .curve
        }

        let bounded = requested.clamped(to: 0...100)
        lastRequestedDuty = bounded
        lastUpdateTime = now
        lastValidTime = now
        return AutoControlDecision(
            timestamp: now,
            valid: true,
            requestedDuty: bounded,
            reason: reason,
            temperatureCelsius: temperature,
            temperatureState: sample.state,
            rawCurveDuty: rawDuty
        )
    }

    private func isUsable(sample: TemperatureSample, now: TimeInterval) -> Bool {
        guard sample.valid,
              sample.state != .unknown,
              let temperature = sample.controlTemperatureCelsius else { return false }
        return temperature.isFinite
            && (0...125).contains(temperature)
            && now - sample.timestamp <= configuration.temperatureStaleAfter
    }

    private mutating func invalidDecision(now: TimeInterval) -> AutoControlDecision {
        let withinGrace = lastValidTime.map { now - $0 <= configuration.temperatureGrace } ?? false
        lastUpdateTime = now
        if withinGrace, let previous = lastRequestedDuty {
            return AutoControlDecision(
                timestamp: now,
                valid: true,
                requestedDuty: previous,
                reason: .temperatureGraceHold,
                temperatureCelsius: nil,
                temperatureState: .unknown,
                rawCurveDuty: nil
            )
        }
        return AutoControlDecision(
            timestamp: now,
            valid: false,
            requestedDuty: nil,
            reason: .temperatureUnavailable,
            temperatureCelsius: nil,
            temperatureState: .unknown,
            rawCurveDuty: nil
        )
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, self))
    }
}
