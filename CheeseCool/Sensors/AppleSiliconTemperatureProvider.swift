import Darwin
import Foundation
import IOKit.hidsystem

@objc private protocol CheeseCoolIOHIDEvent: NSObjectProtocol {}

private typealias IOHIDEventSystemClientCreateFunction = @convention(c) (
    CFAllocator?
) -> IOHIDEventSystemClient?
private typealias IOHIDServiceClientCopyEventFunction = @convention(c) (
    IOHIDServiceClient?, Int64, Int32, Int64
) -> CheeseCoolIOHIDEvent?
private typealias IOHIDEventGetFloatValueFunction = @convention(c) (
    CheeseCoolIOHIDEvent?, UInt32
) -> Double

public actor AppleHIDTemperatureSensorSource: TemperatureSensorReadingSource {
    private var runtime: AppleHIDTemperatureRuntime?

    public init() {}

    public func readSensors() async throws -> [RawTemperatureSensor] {
        if runtime == nil {
            runtime = try AppleHIDTemperatureRuntime()
        }
        guard let runtime else { throw SensorError.unavailable }
        return runtime.readSensors()
    }

    public nonisolated static func isSoCDieSensor(_ name: String) -> Bool {
        name.range(
            of: #"^(PMU|PMU2) tdie[0-9]+$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
}

private final class AppleHIDTemperatureRuntime: @unchecked Sendable {
    private let handle: UnsafeMutableRawPointer
    private let client: IOHIDEventSystemClient
    private let services: [IOHIDServiceClient]
    private let copyEvent: IOHIDServiceClientCopyEventFunction
    private let getFloat: IOHIDEventGetFloatValueFunction

    init() throws {
        guard let handle = dlopen(
            "/System/Library/Frameworks/IOKit.framework/IOKit",
            RTLD_NOW | RTLD_LOCAL
        ) else {
            throw SensorError.failed("IOKit could not be loaded")
        }
        guard let createSymbol = dlsym(handle, "IOHIDEventSystemClientCreate"),
              let copyEventSymbol = dlsym(handle, "IOHIDServiceClientCopyEvent"),
              let getFloatSymbol = dlsym(handle, "IOHIDEventGetFloatValue") else {
            dlclose(handle)
            throw SensorError.unavailable
        }
        let createClient = unsafeBitCast(
            createSymbol,
            to: IOHIDEventSystemClientCreateFunction.self
        )
        self.copyEvent = unsafeBitCast(
            copyEventSymbol,
            to: IOHIDServiceClientCopyEventFunction.self
        )
        self.getFloat = unsafeBitCast(
            getFloatSymbol,
            to: IOHIDEventGetFloatValueFunction.self
        )
        guard let client = createClient(kCFAllocatorDefault),
              let services = IOHIDEventSystemClientCopyServices(client)
                as? [IOHIDServiceClient] else {
            dlclose(handle)
            throw SensorError.unavailable
        }
        self.handle = handle
        self.client = client
        self.services = services
    }

    deinit {
        dlclose(handle)
    }

    func readSensors() -> [RawTemperatureSensor] {
        services.compactMap { service -> RawTemperatureSensor? in
            guard let property = IOHIDServiceClientCopyProperty(
                service,
                "Product" as CFString
            ) else { return nil }
            let name = String(describing: property)
            guard AppleHIDTemperatureSensorSource.isSoCDieSensor(name),
                  let event = copyEvent(service, 15, 0, 0) else { return nil }
            return RawTemperatureSensor(
                name: name,
                celsius: getFloat(event, UInt32(15 << 16))
            )
        }
    }
}

public actor AppleSiliconTemperatureProvider: TemperatureSource, SoCTemperatureProviding {
    private let source: any TemperatureSensorReadingSource
    private let staleAfter: TimeInterval
    private var lastValid: TemperatureSample?
    private var lastAttemptTime: TimeInterval?
    private var lastAttemptResult: TemperatureSample?

    public init(
        source: any TemperatureSensorReadingSource = AppleHIDTemperatureSensorSource(),
        staleAfter: TimeInterval = 5
    ) {
        self.source = source
        self.staleAfter = staleAfter
    }

    public func readTemperature(now: TimeInterval) async -> TemperatureSample {
        if let lastAttemptTime,
           let lastAttemptResult,
           now - lastAttemptTime >= 0,
           now - lastAttemptTime < 0.5,
           !lastAttemptResult.valid || now - lastAttemptResult.timestamp <= staleAfter {
            return lastAttemptResult
        }
        lastAttemptTime = now
        let started = ContinuousClock.now
        do {
            let sensors = try await source.readSensors()
            let valid = sensors.filter {
                AppleHIDTemperatureSensorSource.isSoCDieSensor($0.name)
                    && $0.celsius.isFinite
                    && (0...125).contains($0.celsius)
            }
            guard let maximum = valid.map(\.celsius).max() else {
                return staleOrUnavailable(now: now, status: .empty)
            }
            let sample = TemperatureClassifier.sample(
                temperature: maximum,
                timestamp: now,
                now: now,
                sourceStatus: .ok,
                staleAfter: staleAfter,
                sensorCount: valid.count,
                sensorsUsed: valid.map(\.name).sorted()
            )
            lastValid = sample
            lastAttemptResult = sample
            _ = started.duration(to: .now)
            return sample
        } catch {
            let sample = staleOrUnavailable(now: now, status: .unavailable)
            lastAttemptResult = sample
            return sample
        }
    }

    public func readSoCTemperature(now: TimeInterval) async -> MetricSample {
        let started = ContinuousClock.now
        let sample = await readTemperature(now: now)
        let latency = Self.milliseconds(started.duration(to: .now))
        guard sample.valid, let value = sample.controlTemperatureCelsius else {
            return .unavailable(
                timestamp: sample.timestamp,
                source: "Apple HID PMU/PMU2 tdie",
                status: sample.sourceStatus,
                reason: Self.reason(for: sample.sourceStatus),
                latencyMilliseconds: latency
            )
        }
        return .valid(
            value,
            timestamp: sample.timestamp,
            source: "Apple HID PMU/PMU2 tdie (\(sample.sensorCount))",
            latencyMilliseconds: latency,
            sensorCount: sample.sensorCount,
            sensorsUsed: sample.sensorsUsed
        )
    }

    private func staleOrUnavailable(
        now: TimeInterval,
        status: SensorSourceStatus
    ) -> TemperatureSample {
        if let lastValid,
           now - lastValid.timestamp <= staleAfter,
           let value = lastValid.controlTemperatureCelsius {
            return TemperatureClassifier.sample(
                temperature: value,
                timestamp: lastValid.timestamp,
                now: now,
                staleAfter: staleAfter,
                sensorCount: lastValid.sensorCount,
                sensorsUsed: lastValid.sensorsUsed
            )
        }
        let timestamp = lastValid?.timestamp ?? now
        return TemperatureClassifier.sample(
            temperature: nil,
            timestamp: timestamp,
            now: now,
            sourceStatus: lastValid == nil ? status : .stale,
            staleAfter: staleAfter
        )
    }

    private static func reason(for status: SensorSourceStatus) -> String {
        switch status {
        case .stale: return "Temperature sample is older than 5 seconds"
        case .empty: return "No valid PMU/PMU2 tdie sensor value"
        default: return "Temperature source unavailable"
        }
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
