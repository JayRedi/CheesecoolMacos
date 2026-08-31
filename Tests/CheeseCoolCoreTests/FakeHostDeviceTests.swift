import XCTest
@testable import CheeseCoolCore

final class FakeHostDeviceTests: XCTestCase {
    func testExactDutyAndMinimumSpeedSemantics() async throws {
        let clock = ManualClock()
        let device = FakeHostDevice(clock: clock)
        try await device.connect()
        try await device.setHostControlled()
        for duty in [0, 50, 100] {
            try await device.setDuty(duty)
            let status = await device.peekStatus()
            XCTAssertEqual(status.targetDuty, duty)
            XCTAssertEqual(status.actualDuty, duty)
        }
        try await device.setDuty(0)
        let status = await device.peekStatus()
        XCTAssertEqual(status.rpm, 345)
        XCTAssertGreaterThan(status.rpm, 0)
    }

    func testMaxUsesDedicatedDeviceMode() async throws {
        let device = FakeHostDevice(clock: ManualClock())
        try await device.connect()
        try await device.setMax()
        let status = await device.peekStatus()
        XCTAssertEqual(status.mode, .max)
        XCTAssertEqual(status.actualDuty, 100)
    }

    func testWatchdogEntersFiftyPercentFailsafeAtThirtySeconds() async throws {
        let clock = ManualClock()
        let device = FakeHostDevice(clock: clock)
        try await device.connect()
        try await device.setHostControlled()
        try await device.setDuty(20)
        try clock.advance(by: 30)
        let status = await device.peekStatus()
        XCTAssertTrue(status.failsafe)
        XCTAssertEqual(status.actualDuty, 50)
    }

    func testStatusKeepaliveRefreshesWatchdog() async throws {
        let clock = ManualClock()
        let device = FakeHostDevice(clock: clock)
        try await device.connect()
        try await device.setHostControlled()
        try await device.setDuty(20)
        for _ in 0..<24 {
            try clock.advance(by: 5)
            let status = try await device.getStatus()
            XCTAssertFalse(status.failsafe)
        }
    }

    func testRebootAndBoundedHistory() async throws {
        let device = FakeHostDevice(clock: ManualClock(), commandHistoryCapacity: 4)
        try await device.connect()
        try await device.setHostControlled()
        for duty in 0..<10 { try await device.setDuty(duty) }
        let historyCount = await device.commandHistory().count
        XCTAssertEqual(historyCount, 4)
        await device.reboot()
        let status = await device.peekStatus()
        let connected = await device.isConnected
        XCTAssertFalse(connected)
        XCTAssertEqual(status.mode, .hostControlled)
        XCTAssertEqual(status.targetDuty, 0)
    }

    func testFailureInjection() async throws {
        let device = FakeHostDevice(clock: ManualClock())
        await device.injectConnectFailure()
        await XCTAssertThrowsErrorAsync { try await device.connect() }
        try await device.connect()
        await device.injectCommandFailure()
        await XCTAssertThrowsErrorAsync { try await device.setHostControlled() }
        await device.injectReadFailure()
        await XCTAssertThrowsErrorAsync { _ = try await device.getStatus() }
        await device.injectTimeout()
        await XCTAssertThrowsErrorAsync { _ = try await device.getStatus() }
    }
}

private func XCTAssertThrowsErrorAsync(
    _ operation: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await operation()
        XCTFail("Expected operation to throw", file: file, line: line)
    } catch {}
}
