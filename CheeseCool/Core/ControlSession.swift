import Foundation

public enum ControlSessionError: Error, LocalizedError, Sendable {
    case missingDutyForHostControl
    case failsafeStillActive
    case modeVerificationFailed
    case dutyVerificationFailed(expected: Int, actual: Int)
    case invalidManualDuty(Int)

    public var errorDescription: String? {
        switch self {
        case .missingDutyForHostControl:
            return "HOST_CONTROLLED recovery requires a duty"
        case .failsafeStillActive:
            return "Device remains in failsafe after recovery"
        case .modeVerificationFailed:
            return "Device mode recovery verification failed"
        case .dutyVerificationFailed(let expected, let actual):
            return "Duty recovery verification failed (expected \(expected), actual \(actual))"
        case .invalidManualDuty(let duty):
            return "Manual duty must be 0 through 100 (received \(duty))"
        }
    }
}

public actor ControlSession {
    private let temperatureSource: any TemperatureSource
    private let device: any HostDevice
    private let clock: any MonotonicClock
    public let events: EventLog

    private var configuration: Configuration
    private var autoController: AutoController
    private var operatingMode: OperatingMode
    private var manualDuty: Int
    private var connectionState: ConnectionState = .disconnected
    private var controlState: ControlState = .idle
    private var lastSample: TemperatureSample?
    private var lastDecision: ControlDecision?
    private var lastStatus: DeviceStatus?
    private var lastSentDuty: Int?
    private var lastCommand: String?
    private var lastCommandTime: TimeInterval?
    private var lastError: String?
    private var stopped = false
    private var sleeping = false
    private var needsRestore = true
    private var temperatureSuspended = false
    private var temperatureLostLogged = false
    private var powerFaultLatched = false
    private var reconnectAttempts = 0
    private var nextReconnectTime: TimeInterval = 0

    public init(
        temperatureSource: any TemperatureSource,
        device: any HostDevice,
        configuration: Configuration = .defaults,
        clock: any MonotonicClock = SystemMonotonicClock(),
        eventLog: EventLog = EventLog()
    ) {
        self.temperatureSource = temperatureSource
        self.device = device
        self.configuration = configuration
        self.clock = clock
        self.events = eventLog
        self.autoController = AutoController(configuration: configuration)
        self.operatingMode = configuration.operatingMode
        self.manualDuty = configuration.manualDuty
    }

    public var currentControlState: ControlState { controlState }
    public var currentConnectionState: ConnectionState { connectionState }
    public var currentOperatingMode: OperatingMode { operatingMode }

    @discardableResult
    public func tick() async -> TelemetrySnapshot {
        let now = clock.now
        if stopped {
            controlState = .stopped
            return telemetry(at: now)
        }
        if sleeping {
            controlState = .sleeping
            return telemetry(at: now)
        }

        guard let decision = await desiredDecision(at: now) else {
            lastDecision = nil
            return telemetry(at: now)
        }
        lastDecision = decision
        guard await ensureConnected(for: decision) else { return telemetry(at: now) }

        do {
            switch operatingMode {
            case .auto:
                if let duty = decision.requestedDuty, duty != lastSentDuty {
                    try await setDuty(duty)
                }
                if controlState != .temperatureGrace { controlState = .autoActive }
            case .manual:
                if decision.requestedDuty != lastSentDuty,
                   let duty = decision.requestedDuty {
                    try await setDuty(duty)
                }
                controlState = .manualActive
            case .max:
                controlState = .maxActive
            }

            if statusRefreshDue(at: now) {
                let status = try await getStatus()
                if status.powerFault {
                    await enterPowerFault(status)
                } else if status.failsafe {
                    try await restoreMode(for: decision, from: status)
                }
            }
        } catch {
            await deviceFailure(error)
        }
        return telemetry(at: clock.now)
    }

    public func setMode(_ mode: OperatingMode, manualDuty newDuty: Int? = nil) async throws {
        if let newDuty {
            guard (0...100).contains(newDuty) else {
                throw ControlSessionError.invalidManualDuty(newDuty)
            }
            manualDuty = newDuty
        }
        let requestedManualDuty = mode == .manual ? (newDuty ?? manualDuty) : nil
        if mode != operatingMode || (mode == .manual && requestedManualDuty != lastSentDuty) {
            let old = operatingMode
            operatingMode = mode
            needsRestore = true
            await events.append(
                timestamp: clock.now,
                type: .modeChanged,
                detail: "\(old.rawValue)->\(mode.rawValue)"
            )
        }
    }

    public func applyConfiguration(_ newConfiguration: Configuration) async throws {
        try newConfiguration.validate()
        configuration = newConfiguration
        autoController = AutoController(configuration: newConfiguration)
        manualDuty = newConfiguration.manualDuty
        if !newConfiguration.restorePreviousMode {
            operatingMode = newConfiguration.operatingMode
        }
        needsRestore = true
    }

    public func requestReconnect() async {
        guard !sleeping, !stopped else { return }
        await device.disconnect()
        connectionState = .disconnected
        reconnectAttempts = 0
        nextReconnectTime = clock.now
        needsRestore = true
    }

    public func acknowledgePowerFault() async {
        powerFaultLatched = false
        await requestReconnect()
    }

    public func prepareForSleep() async {
        guard !stopped else { return }
        sleeping = true
        await device.disconnect()
        connectionState = .disconnected
        controlState = .sleeping
        await events.append(timestamp: clock.now, type: .sleep)
    }

    public func resumeFromSleep() async {
        guard !stopped else { return }
        sleeping = false
        needsRestore = true
        reconnectAttempts = 0
        nextReconnectTime = clock.now
        controlState = .recovering
        await events.append(timestamp: clock.now, type: .wake)
    }

    public func stop() async {
        guard !stopped else { return }
        await device.close()
        connectionState = .disconnected
        controlState = .stopped
        stopped = true
        await events.append(timestamp: clock.now, type: .stopped)
    }

    public func telemetry() -> TelemetrySnapshot {
        telemetry(at: clock.now)
    }

    /// Reads fresh device telemetry without waiting for temperature sampling or
    /// changing the requested control mode. This keeps the UI's fan RPM cadence
    /// independent from a slow system-sensor read.
    @discardableResult
    public func refreshStatus() async -> TelemetrySnapshot {
        let now = clock.now
        guard !stopped, !sleeping,
              connectionState == .connected,
              await device.isConnected,
              statusRefreshDue(at: now) else {
            return telemetry(at: now)
        }
        do {
            let status = try await getStatus()
            if status.powerFault {
                await enterPowerFault(status)
            } else if status.failsafe {
                needsRestore = true
            }
        } catch {
            await deviceFailure(error)
        }
        return telemetry(at: clock.now)
    }

    private func desiredDecision(at now: TimeInterval) async -> ControlDecision? {
        switch operatingMode {
        case .max:
            return ControlDecision(
                requestedMode: .max,
                requestedDuty: nil,
                reason: "MAX_MODE",
                timestamp: now
            )
        case .manual:
            return ControlDecision(
                requestedMode: .manual,
                requestedDuty: manualDuty,
                reason: manualDuty == 0 ? "MANUAL_DUTY_MINIMUM_SPEED" : "MANUAL_DUTY",
                timestamp: now
            )
        case .auto:
            let sample = await temperatureSource.readTemperature(now: now)
            lastSample = sample
            let autoDecision = autoController.update(sample: sample, now: now)
            switch autoDecision.reason {
            case .temperatureGraceHold:
                controlState = .temperatureGrace
                if !temperatureLostLogged {
                    await events.append(timestamp: now, type: .temperatureLost, detail: "grace hold")
                    temperatureLostLogged = true
                }
            case .temperatureUnavailable:
                controlState = .temperatureUnavailable
                if !temperatureLostLogged {
                    await events.append(timestamp: now, type: .temperatureLost, detail: "unavailable")
                    temperatureLostLogged = true
                }
                if !temperatureSuspended {
                    await events.append(timestamp: now, type: .failsafeHandoff, detail: "stop all traffic")
                }
                temperatureSuspended = true
                return nil
            default:
                if temperatureLostLogged {
                    await events.append(timestamp: now, type: .temperatureRecovered)
                }
                if temperatureSuspended {
                    controlState = .recovering
                    needsRestore = true
                }
                temperatureLostLogged = false
                temperatureSuspended = false
            }
            let duty = autoDecision.requestedDuty.map {
                min(100, max(0, Int($0.rounded(.toNearestOrEven))))
            }
            return ControlDecision(
                requestedMode: .auto,
                requestedDuty: duty,
                reason: autoDecision.reason.rawValue,
                timestamp: now,
                rawAutoDuty: autoDecision.rawCurveDuty
            )
        }
    }

    private func ensureConnected(for decision: ControlDecision) async -> Bool {
        if powerFaultLatched {
            controlState = .powerFault
            return false
        }
        let deviceConnected = await device.isConnected
        if connectionState != .connected || !deviceConnected {
            return await connectAndSynchronize(for: decision)
        }
        if needsRestore {
            do {
                let status = try await getStatus()
                if status.powerFault {
                    await enterPowerFault(status)
                    return false
                }
                try await restoreMode(for: decision, from: status)
            } catch {
                await deviceFailure(error)
                return false
            }
        }
        return true
    }

    private func connectAndSynchronize(for decision: ControlDecision) async -> Bool {
        let now = clock.now
        guard reconnectAttempts < configuration.reconnectPolicy.maxAttempts else {
            connectionState = .unavailable
            controlState = .deviceUnavailable
            return false
        }
        guard now >= nextReconnectTime else { return false }

        connectionState = .connecting
        controlState = .recovering
        reconnectAttempts += 1
        await events.append(
            timestamp: now,
            type: .deviceConnecting,
            detail: String(reconnectAttempts)
        )
        do {
            try await device.connect()
            connectionState = .connected
            await events.append(timestamp: now, type: .deviceConnected)
            let status = try await getStatus()
            if status.powerFault {
                await enterPowerFault(status)
                return false
            }
            try await restoreMode(for: decision, from: status)
            reconnectAttempts = 0
            nextReconnectTime = now
            lastError = nil
            return !powerFaultLatched
        } catch {
            await deviceFailure(error)
            return false
        }
    }

    private func restoreMode(for decision: ControlDecision, from status: DeviceStatus) async throws {
        controlState = .recovering
        if status.failsafe {
            await events.append(
                timestamp: clock.now,
                type: .recovery,
                detail: "recover from MCU failsafe"
            )
        }

        if decision.requestedMode == .max {
            try await setMax()
        } else {
            try await setHostControlled()
            guard let duty = decision.requestedDuty else {
                throw ControlSessionError.missingDutyForHostControl
            }
            try await setDuty(duty)
        }

        let verified = try await getStatus()
        if verified.powerFault {
            await enterPowerFault(verified)
            return
        }
        guard !verified.failsafe else { throw ControlSessionError.failsafeStillActive }
        if decision.requestedMode == .max {
            guard verified.mode == .max, verified.targetDuty == 100 else {
                throw ControlSessionError.modeVerificationFailed
            }
        } else if verified.targetDuty != decision.requestedDuty {
            throw ControlSessionError.dutyVerificationFailed(
                expected: decision.requestedDuty ?? -1,
                actual: verified.targetDuty
            )
        }
        needsRestore = false
        controlState = activeState(for: operatingMode)
    }

    private func deviceFailure(_ error: Error) async {
        let now = clock.now
        lastError = error.localizedDescription
        connectionState = .unavailable
        controlState = .deviceUnavailable
        await device.disconnect()
        await events.append(timestamp: now, type: .commandError, detail: error.localizedDescription)
        await events.append(timestamp: now, type: .deviceDisconnected, detail: "transport failure")
        if reconnectAttempts < configuration.reconnectPolicy.maxAttempts {
            let exponent = max(0, reconnectAttempts - 1)
            let delay = configuration.reconnectPolicy.initialDelay
                * pow(configuration.reconnectPolicy.backoffMultiplier, Double(exponent))
            nextReconnectTime = now + min(delay, configuration.reconnectPolicy.maxDelay)
        }
    }

    private func enterPowerFault(_ status: DeviceStatus) async {
        lastStatus = status
        powerFaultLatched = true
        controlState = .powerFault
        await events.append(timestamp: clock.now, type: .powerFault, detail: "device powerFault=1")
    }

    private func setHostControlled() async throws {
        try await device.setHostControlled()
        recordCommand("SET_MODE(HOST_CONTROLLED)")
    }

    private func setMax() async throws {
        try await device.setMax()
        recordCommand("SET_MODE(MAX)")
    }

    private func setDuty(_ duty: Int) async throws {
        try await device.setDuty(duty)
        recordCommand("SET_DUTY(\(duty))")
        lastSentDuty = duty
    }

    private func getStatus() async throws -> DeviceStatus {
        let status = try await device.getStatus()
        recordCommand("GET_STATUS")
        lastStatus = status
        return status
    }

    private func recordCommand(_ command: String) {
        lastCommand = command
        lastCommandTime = clock.now
    }

    /// Status drives the displayed fan RPM, so it follows the user-facing refresh
    /// interval. The keepalive ceiling remains a safety bound when the UI is set
    /// to a slower interval.
    private func statusRefreshDue(at now: TimeInterval) -> Bool {
        guard let lastCommandTime else { return true }
        let interval = min(configuration.refreshInterval, configuration.keepaliveInterval)
        return now - lastCommandTime >= interval
    }

    private func activeState(for mode: OperatingMode) -> ControlState {
        switch mode {
        case .auto: return .autoActive
        case .manual: return .manualActive
        case .max: return .maxActive
        }
    }

    private func telemetry(at now: TimeInterval) -> TelemetrySnapshot {
        TelemetrySnapshot(
            timestamp: now,
            socTemperatureCelsius: lastSample?.controlTemperatureCelsius,
            temperatureState: lastSample?.state ?? .unknown,
            temperatureValid: lastSample?.valid ?? false,
            operatingMode: operatingMode,
            controlState: controlState,
            rawAutoDuty: lastDecision?.rawAutoDuty,
            requestedDuty: lastDecision?.requestedDuty,
            lastSentDuty: lastSentDuty,
            deviceTargetDuty: lastStatus?.targetDuty,
            deviceActualDuty: lastStatus?.actualDuty,
            rpm: lastStatus?.rpm,
            failsafe: lastStatus?.failsafe,
            powerFault: lastStatus?.powerFault,
            connectionState: connectionState,
            lastCommand: lastCommand,
            lastCommandAge: lastCommandTime.map { max(0, now - $0) },
            lastError: lastError,
            reason: lastDecision?.reason ?? "",
            physicalFanOffSupported: configuration.physicalFanOffSupported
        )
    }
}
