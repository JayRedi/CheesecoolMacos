import Foundation

public actor FakeHostDevice: HostDevice {
    private let clock: any MonotonicClock
    private let watchdogInterval: TimeInterval
    private let failsafeDuty: Int
    private let commandHistoryCapacity: Int

    private var usbAvailable = true
    private var connected = false
    private var mode: DeviceMode = .hostControlled
    private var targetDuty = 0
    private var actualDuty = 0
    private var failsafe = false
    private var powerFault = false
    private var usbConfigured = true
    private let firmwareVersion = FirmwareVersion("fake-protocol-v1")
    private var bootTime: TimeInterval
    private var lastHostActivity: TimeInterval?
    private var failNextCommand = false
    private var failNextRead = false
    private var failNextConnect = false
    private var timeoutNextOperation = false
    private var history: [DeviceCommandRecord] = []

    public private(set) var connectAttempts = 0
    public private(set) var readCount = 0
    public private(set) var totalCommandCount = 0

    public init(
        clock: any MonotonicClock,
        watchdogInterval: TimeInterval = 30,
        failsafeDuty: Int = 50,
        commandHistoryCapacity: Int = 512
    ) {
        precondition(watchdogInterval > 0)
        precondition((0...100).contains(failsafeDuty))
        precondition(commandHistoryCapacity > 0)
        self.clock = clock
        self.watchdogInterval = watchdogInterval
        self.failsafeDuty = failsafeDuty
        self.commandHistoryCapacity = commandHistoryCapacity
        self.bootTime = clock.now
    }

    public var isConnected: Bool { connected && usbAvailable }

    public func connect() throws {
        connectAttempts += 1
        if failNextConnect {
            failNextConnect = false
            throw HostDeviceError.unavailable("Simulated connection failure")
        }
        guard usbAvailable else { throw HostDeviceError.unavailable("USB unavailable") }
        if timeoutNextOperation {
            timeoutNextOperation = false
            throw HostDeviceError.timeout("Simulated connection timeout")
        }
        connected = true
    }

    public func disconnect() {
        connected = false
    }

    public func close() {
        disconnect()
    }

    public func getStatus() throws -> DeviceStatus {
        applyWatchdog()
        try requireConnection()
        if failNextRead {
            failNextRead = false
            throw HostDeviceError.readFailed("Simulated status read failure")
        }
        if timeoutNextOperation {
            timeoutNextOperation = false
            throw HostDeviceError.timeout("Simulated status read timeout")
        }
        lastHostActivity = clock.now
        readCount += 1
        record(command: "GET_STATUS")
        return status()
    }

    public func setHostControlled() throws {
        try beforeCommand("SET_MODE_HOST_CONTROLLED", value: 0)
        mode = .hostControlled
        failsafe = false
    }

    public func setMax() throws {
        try beforeCommand("SET_MODE_MAX", value: 1)
        mode = .max
        failsafe = false
        targetDuty = 100
        actualDuty = 100
    }

    public func setDuty(_ percent: Int) throws {
        guard (0...100).contains(percent) else { throw HostDeviceError.invalidDuty(percent) }
        try beforeCommand("SET_DUTY", value: percent)
        guard mode == .hostControlled else {
            throw HostDeviceError.commandFailed("SET_DUTY requires HOST_CONTROLLED mode")
        }
        targetDuty = percent
        actualDuty = percent
    }

    public func peekStatus() -> DeviceStatus {
        applyWatchdog()
        return status()
    }

    public func commandHistory() -> [DeviceCommandRecord] { history }

    public func setUSBAvailable(_ available: Bool) {
        usbAvailable = available
        if !available { connected = false }
    }

    public func injectCommandFailure() { failNextCommand = true }
    public func injectReadFailure() { failNextRead = true }
    public func injectConnectFailure() { failNextConnect = true }
    public func injectTimeout() { timeoutNextOperation = true }
    public func setPowerFault(_ active: Bool) { powerFault = active }

    public func reboot() {
        connected = false
        mode = .hostControlled
        targetDuty = 0
        actualDuty = 0
        failsafe = false
        lastHostActivity = nil
        bootTime = clock.now
    }

    private func applyWatchdog() {
        guard let lastHostActivity,
              !failsafe,
              clock.now - lastHostActivity >= watchdogInterval else { return }
        failsafe = true
        mode = .hostControlled
        targetDuty = failsafeDuty
        actualDuty = failsafeDuty
    }

    private func requireConnection() throws {
        guard usbAvailable, connected else {
            connected = false
            throw HostDeviceError.unavailable("USB device unavailable")
        }
    }

    private func beforeCommand(_ command: String, value: Int?) throws {
        applyWatchdog()
        try requireConnection()
        if timeoutNextOperation {
            timeoutNextOperation = false
            throw HostDeviceError.timeout("Simulated transfer timeout: \(command)")
        }
        if failNextCommand {
            failNextCommand = false
            throw HostDeviceError.commandFailed("Simulated command failure: \(command)")
        }
        lastHostActivity = clock.now
        record(command: command, value: value)
    }

    private func record(command: String, value: Int? = nil) {
        history.append(DeviceCommandRecord(timestamp: clock.now, command: command, value: value))
        if history.count > commandHistoryCapacity {
            history.removeFirst(history.count - commandHistoryCapacity)
        }
        totalCommandCount += 1
    }

    private func status() -> DeviceStatus {
        DeviceStatus(
            mode: mode,
            targetDuty: targetDuty,
            actualDuty: actualDuty,
            rpm: rpm(for: actualDuty),
            usbConfigured: usbConfigured && usbAvailable,
            failsafe: failsafe,
            powerFault: powerFault,
            uptime: max(0, clock.now - bootTime),
            firmwareVersion: firmwareVersion
        )
    }

    private func rpm(for duty: Int) -> Int {
        if duty == 0 { return 345 }
        return Int((345 + (2_500 - 345) * Double(duty) / 100).rounded())
    }
}
