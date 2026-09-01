import XCTest
@testable import CheeseCoolCore

final class ControlSessionTests: XCTestCase {
    private func makeSession(
        temperature: Double = 50,
        configuration: Configuration = .defaults,
        eventCapacity: Int = 128
    ) -> (ManualClock, FakeSensorProvider, FakeHostDevice, EventLog, ControlSession) {
        let clock = ManualClock()
        let source = FakeSensorProvider(temperature: temperature)
        let device = FakeHostDevice(clock: clock)
        let events = EventLog(capacity: eventCapacity)
        let session = ControlSession(
            temperatureSource: source,
            device: device,
            configuration: configuration,
            clock: clock,
            eventLog: events
        )
        return (clock, source, device, events, session)
    }

    func testAutoNormalAndNoDuplicateDutyCommands() async throws {
        let (clock, _, device, _, session) = makeSession()
        let first = await session.tick()
        let firstStatus = await device.peekStatus()
        XCTAssertEqual(first.controlState, .autoActive)
        XCTAssertEqual(firstStatus.actualDuty, 25)
        let initial = await device.commandHistory().filter { $0.command == "SET_DUTY" }.count
        for _ in 0..<4 { try clock.advance(by: 1); _ = await session.tick() }
        let unchanged = await device.commandHistory().filter { $0.command == "SET_DUTY" }.count
        XCTAssertEqual(unchanged, initial)
        try clock.advance(by: 1)
        _ = await session.tick()
        let hasKeepalive = await device.commandHistory().contains { $0.command == "GET_STATUS" }
        XCTAssertTrue(hasKeepalive)
    }

    func testStatusPollingUsesConfiguredRefreshInterval() async throws {
        let configuration = try Configuration(keepaliveInterval: 5, refreshInterval: 1)
        let (clock, _, device, _, session) = makeSession(configuration: configuration)
        _ = await session.tick()
        let readsBefore = await device.readCount

        try clock.advance(by: 1)
        _ = await session.tick()

        let readsAfter = await device.readCount
        XCTAssertEqual(readsAfter, readsBefore + 1)
    }

    func testDedicatedStatusRefreshDoesNotNeedTemperatureSampling() async throws {
        let configuration = try Configuration(keepaliveInterval: 5, refreshInterval: 1)
        let (clock, source, device, _, session) = makeSession(configuration: configuration)
        try await session.setMode(.manual, manualDuty: 20)
        _ = await session.tick()
        await source.setUnavailable()
        let readsBefore = await device.readCount

        try clock.advance(by: 1)
        let telemetry = await session.refreshStatus()

        let readsAfter = await device.readCount
        XCTAssertEqual(readsAfter, readsBefore + 1)
        XCTAssertEqual(telemetry.rpm, 776)
        XCTAssertEqual(telemetry.connectionState, .connected)
    }

    func testControlAndStatusRefreshNeverOverlapDeviceTransactions() async throws {
        let configuration = try Configuration(keepaliveInterval: 5, refreshInterval: 1)
        let clock = ManualClock()
        let source = FakeSensorProvider(temperature: 50)
        let device = DelayedHostDevice(base: FakeHostDevice(clock: clock))
        let session = ControlSession(
            temperatureSource: source,
            device: device,
            configuration: configuration,
            clock: clock
        )
        _ = await session.tick()

        try clock.advance(by: 1)
        async let controlTick = session.tick()
        try await Task.sleep(for: .milliseconds(20))
        async let statusRefresh = session.refreshStatus()
        let (controlTelemetry, statusTelemetry) = await (controlTick, statusRefresh)
        let maximumConcurrentOperations = await device.maximumConcurrentOperations

        XCTAssertEqual(controlTelemetry.connectionState, .connected)
        XCTAssertEqual(statusTelemetry.connectionState, .connected)
        XCTAssertEqual(maximumConcurrentOperations, 1)
    }

    func testManualZeroFiftyAndHundred() async throws {
        let (_, _, device, _, session) = makeSession()
        for duty in [0, 50, 100] {
            try await session.setMode(.manual, manualDuty: duty)
            let telemetry = await session.tick()
            let status = await device.peekStatus()
            XCTAssertEqual(status.actualDuty, duty)
            XCTAssertEqual(telemetry.controlState, .manualActive)
            if duty == 0 {
                XCTAssertEqual(status.rpm, 345)
                XCTAssertFalse(telemetry.physicalFanOffSupported)
            }
        }
    }

    func testMaxUsesSetMaxNotSetDutyHundred() async throws {
        let (_, _, device, _, session) = makeSession()
        try await session.setMode(.max)
        _ = await session.tick()
        let commands = await device.commandHistory()
        XCTAssertTrue(commands.contains { $0.command == "SET_MODE_MAX" })
        XCTAssertFalse(commands.contains { $0.command == "SET_DUTY" && $0.value == 100 })
    }

    func testModeTransitionMatrix() async throws {
        let (_, source, device, _, session) = makeSession(temperature: 60)
        _ = await session.tick()
        try await session.setMode(.manual, manualDuty: 42)
        _ = await session.tick()
        var status = await device.peekStatus()
        XCTAssertEqual(status.actualDuty, 42)
        try await session.setMode(.auto)
        _ = await session.tick()
        var controlState = await session.currentControlState
        XCTAssertEqual(controlState, .autoActive)
        try await session.setMode(.max)
        _ = await session.tick()
        status = await device.peekStatus()
        XCTAssertEqual(status.mode, .max)
        await source.setTemperature(70)
        try await session.setMode(.auto)
        _ = await session.tick()
        status = await device.peekStatus()
        controlState = await session.currentControlState
        XCTAssertEqual(status.mode, .hostControlled)
        XCTAssertEqual(controlState, .autoActive)
    }

    func testTemperatureGraceThenAllTrafficStopsAndMCUFailsafeOwnsFan() async throws {
        let (clock, source, device, _, session) = makeSession(temperature: 60)
        _ = await session.tick()
        await source.setUnavailable()
        try clock.advance(by: 1)
        _ = await session.tick()
        var state = await session.currentControlState
        XCTAssertEqual(state, .temperatureGrace)
        try clock.advance(by: 3)
        _ = await session.tick()
        state = await session.currentControlState
        XCTAssertEqual(state, .temperatureUnavailable)
        let traffic = await device.commandHistory().count
        let reads = await device.readCount
        for _ in 0..<35 { try clock.advance(by: 1); _ = await session.tick() }
        let trafficAfter = await device.commandHistory().count
        let readsAfter = await device.readCount
        XCTAssertEqual(trafficAfter, traffic)
        XCTAssertEqual(readsAfter, reads)
        let status = await device.peekStatus()
        XCTAssertTrue(status.failsafe)
        XCTAssertEqual(status.actualDuty, 50)
    }

    func testTemperatureRecoveryReadsRestoresAppliesAndVerifies() async throws {
        let (clock, source, device, _, session) = makeSession(temperature: 60)
        _ = await session.tick()
        await source.setUnavailable()
        try clock.advance(by: 4)
        _ = await session.tick()
        try clock.advance(by: 30)
        var status = await device.peekStatus()
        XCTAssertTrue(status.failsafe)
        let before = await device.commandHistory().count
        await source.setTemperature(55)
        try clock.advance(by: 1)
        _ = await session.tick()
        let recovery = Array((await device.commandHistory()).dropFirst(before)).map(\.command)
        XCTAssertEqual(Array(recovery.prefix(4)), ["GET_STATUS", "SET_MODE_HOST_CONTROLLED", "SET_DUTY", "GET_STATUS"])
        status = await device.peekStatus()
        let state = await session.currentControlState
        XCTAssertFalse(status.failsafe)
        XCTAssertEqual(state, .autoActive)
    }

    func testManualAndMaxIgnoreTemperatureAvailability() async throws {
        let (clock, source, device, _, session) = makeSession()
        await source.setUnavailable()
        try await session.setMode(.manual, manualDuty: 30)
        _ = await session.tick()
        var status = await device.peekStatus()
        XCTAssertEqual(status.actualDuty, 30)
        try clock.advance(by: 10)
        _ = await session.tick()
        try await session.setMode(.max)
        _ = await session.tick()
        status = await device.peekStatus()
        XCTAssertEqual(status.actualDuty, 100)
    }

    func testDisconnectUsesBoundedReconnectPolicy() async throws {
        let configuration = try Configuration(
            reconnectPolicy: ReconnectPolicy(maxAttempts: 3, initialDelay: 2, maxDelay: 8)
        )
        let (clock, _, device, _, session) = makeSession(configuration: configuration)
        _ = await session.tick()
        await device.setUSBAvailable(false)
        try clock.advance(by: 5)
        _ = await session.tick()
        for _ in 0..<20 { try clock.advance(by: 10); _ = await session.tick() }
        let state = await session.currentControlState
        let attempts = await device.connectAttempts
        XCTAssertEqual(state, .deviceUnavailable)
        XCTAssertLessThanOrEqual(attempts, 4)
    }

    func testReconnectRestoresManualMaxAndCurrentAuto() async throws {
        do {
            let (_, _, device, _, session) = makeSession()
            try await session.setMode(.manual, manualDuty: 37)
            _ = await session.tick()
            await device.reboot()
            await session.requestReconnect()
            _ = await session.tick()
            let status = await device.peekStatus()
            XCTAssertEqual(status.actualDuty, 37)
        }
        do {
            let (_, _, device, _, session) = makeSession()
            try await session.setMode(.max)
            _ = await session.tick()
            await device.reboot()
            await session.requestReconnect()
            _ = await session.tick()
            let status = await device.peekStatus()
            XCTAssertEqual(status.mode, .max)
        }
        do {
            let (clock, source, device, _, session) = makeSession()
            _ = await session.tick()
            await device.reboot()
            await source.setTemperature(70)
            try clock.advance(by: 1)
            await session.requestReconnect()
            _ = await session.tick()
            let status = await device.peekStatus()
            XCTAssertGreaterThan(status.actualDuty, 25)
        }
    }

    func testTransportFailuresEnterDeviceUnavailable() async throws {
        for fault in 0..<3 {
            let (clock, _, device, _, session) = makeSession()
            _ = await session.tick()
            if fault == 0 {
                await device.injectCommandFailure()
                try await session.setMode(.manual, manualDuty: 51)
            } else if fault == 1 {
                await device.injectReadFailure()
                try clock.advance(by: 5)
            } else {
                await device.injectTimeout()
                try clock.advance(by: 5)
            }
            _ = await session.tick()
            let state = await session.currentControlState
            XCTAssertEqual(state, .deviceUnavailable)
        }
    }

    func testFailsafeIsExplicitlyRecovered() async throws {
        let (clock, _, device, _, session) = makeSession()
        _ = await session.tick()
        try clock.advance(by: 30)
        var status = await device.peekStatus()
        XCTAssertTrue(status.failsafe)
        _ = await session.tick()
        status = await device.peekStatus()
        let didRestoreMode = await device.commandHistory().contains { $0.command == "SET_MODE_HOST_CONTROLLED" }
        XCTAssertFalse(status.failsafe)
        XCTAssertTrue(didRestoreMode)
    }

    func testPowerFaultLatchesAndRequiresAcknowledgement() async throws {
        let (clock, source, device, _, session) = makeSession()
        _ = await session.tick()
        await device.setPowerFault(true)
        try clock.advance(by: 5)
        _ = await session.tick()
        var state = await session.currentControlState
        XCTAssertEqual(state, .powerFault)
        let traffic = await device.commandHistory().count
        await source.setTemperature(90)
        for _ in 0..<10 { try clock.advance(by: 1); _ = await session.tick() }
        let trafficAfter = await device.commandHistory().count
        XCTAssertEqual(trafficAfter, traffic)
        await device.setPowerFault(false)
        await session.acknowledgePowerFault()
        _ = await session.tick()
        state = await session.currentControlState
        XCTAssertEqual(state, .autoActive)
    }

    func testSleepWakeAndPermanentStop() async throws {
        let (clock, _, device, _, session) = makeSession()
        try await session.setMode(.manual, manualDuty: 44)
        _ = await session.tick()
        await session.prepareForSleep()
        let traffic = await device.commandHistory().count
        for _ in 0..<40 { try clock.advance(by: 1); _ = await session.tick() }
        var trafficAfter = await device.commandHistory().count
        var status = await device.peekStatus()
        XCTAssertEqual(trafficAfter, traffic)
        XCTAssertTrue(status.failsafe)
        await session.resumeFromSleep()
        _ = await session.tick()
        status = await device.peekStatus()
        XCTAssertFalse(status.failsafe)
        XCTAssertEqual(status.actualDuty, 44)
        await session.stop()
        _ = await session.tick()
        trafficAfter = await device.commandHistory().count
        let state = await session.currentControlState
        XCTAssertGreaterThanOrEqual(trafficAfter, traffic)
        XCTAssertEqual(state, .stopped)
    }
}

private actor DelayedHostDevice: HostDevice {
    private let base: FakeHostDevice
    private var activeOperations = 0
    private(set) var maximumConcurrentOperations = 0

    init(base: FakeHostDevice) {
        self.base = base
    }

    var isConnected: Bool { get async { await base.isConnected } }

    func connect() async throws {
        try await base.connect()
    }

    func disconnect() async {
        await base.disconnect()
    }

    func close() async {
        await base.close()
    }

    func getStatus() async throws -> DeviceStatus {
        activeOperations += 1
        maximumConcurrentOperations = max(maximumConcurrentOperations, activeOperations)
        defer { activeOperations -= 1 }
        try? await Task.sleep(for: .milliseconds(100))
        return try await base.getStatus()
    }

    func setHostControlled() async throws {
        try await base.setHostControlled()
    }

    func setMax() async throws {
        try await base.setMax()
    }

    func setDuty(_ percent: Int) async throws {
        try await base.setDuty(percent)
    }
}
