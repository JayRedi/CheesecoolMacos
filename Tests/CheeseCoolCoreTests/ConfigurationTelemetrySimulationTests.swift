import XCTest
@testable import CheeseCoolCore

final class ConfigurationTelemetrySimulationTests: XCTestCase {
    private struct OracleFixture: Decodable {
        struct CurveEntry: Decodable {
            let temperatureCelsius: Double
            let duty: Double
        }

        let oracleCommit: String
        let curve: [CurveEntry]
        let minimumRPMAtZeroDuty: Int
        let watchdogSeconds: Double
        let failsafeDuty: Int
    }

    func testRepresentativePythonOracleFixtureParity() async throws {
        let bundle = Bundle(for: ConfigurationTelemetrySimulationTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "PythonOracleV1", withExtension: "json"))
        let fixture = try JSONDecoder().decode(OracleFixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(fixture.oracleCommit, "50beb2500937bd86aee1478bc1c295fc673b9efb")
        for entry in fixture.curve {
            XCTAssertEqual(
                AutoController.interpolate(temperatureCelsius: entry.temperatureCelsius),
                entry.duty,
                accuracy: 0.000_001
            )
        }

        let clock = ManualClock()
        let device = FakeHostDevice(clock: clock)
        try await device.connect()
        try await device.setHostControlled()
        try await device.setDuty(0)
        var status = await device.peekStatus()
        XCTAssertEqual(status.rpm, fixture.minimumRPMAtZeroDuty)
        try clock.advance(by: fixture.watchdogSeconds)
        status = await device.peekStatus()
        XCTAssertTrue(status.failsafe)
        XCTAssertEqual(status.actualDuty, fixture.failsafeDuty)
    }

    func testConfigurationRoundTripAndStrictFields() throws {
        let configuration = try Configuration(operatingMode: .manual, manualDuty: 0)
        let encoded = try configuration.encoded()
        XCTAssertEqual(try Configuration.decodeStrict(from: encoded), configuration)

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["unknown"] = 1
        let unknown = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try Configuration.decodeStrict(from: unknown))
        object.removeValue(forKey: "unknown")
        object.removeValue(forKey: "deadband")
        let missing = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try Configuration.decodeStrict(from: missing))
    }

    func testConfigurationRejectsInvalidRangesAndNonFiniteNumbers() {
        XCTAssertThrowsError(try Configuration(manualDuty: 101))
        XCTAssertThrowsError(try Configuration(deadband: .nan))
        XCTAssertThrowsError(try Configuration(rampUpPerSecond: .infinity))
        XCTAssertThrowsError(try Configuration(physicalFanOffSupported: true))
        XCTAssertThrowsError(try Configuration(version: 2))
    }

    func testConfigStoreCorruptFallbackAndAtomicSaveUseInjectedDirectory() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = directory.appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("{not-json".utf8).write(to: file)
        let store = ConfigStore(fileURL: file)
        let fallback = await store.load()
        XCTAssertTrue(fallback.usedDefaults)
        XCTAssertNotNil(fallback.error)
        try await store.save(.defaults)
        let loaded = await store.load()
        XCTAssertFalse(loaded.usedDefaults)
        XCTAssertNil(loaded.error)
        XCTAssertEqual(loaded.configuration, .defaults)
    }

    func testEventLogAndDeviceHistoryStayBounded() async {
        let log = EventLog(capacity: 3)
        for index in 0..<10 {
            await log.append(timestamp: Double(index), type: .modeChanged, detail: String(index))
        }
        let count = await log.count
        let firstDetail = await log.snapshot().first?.detail
        XCTAssertEqual(count, 3)
        XCTAssertEqual(firstDetail, "7")
    }

    func testTelemetryIsStructured() async {
        let clock = ManualClock()
        let source = FakeSensorProvider(temperature: 55)
        let device = FakeHostDevice(clock: clock)
        let session = ControlSession(
            temperatureSource: source,
            device: device,
            clock: clock
        )
        let snapshot = await session.tick()
        XCTAssertEqual(snapshot.operatingMode, .auto)
        XCTAssertTrue(snapshot.temperatureValid)
        XCTAssertNotNil(snapshot.rpm)
        XCTAssertNotNil(snapshot.lastCommand)
    }

    func testInstallManifestIsOwnedAndNeverUsesWildcards() {
        let manifest = InstallManifest.standard(homeDirectory: URL(fileURLWithPath: "/tmp/test-home"))
        XCTAssertEqual(manifest.persistentShellEnvironmentVariableCount, 0)
        XCTAssertTrue(manifest.ownedResources.allSatisfy { resource in
            guard let path = resource.path else { return resource.bundleIdentifier != nil }
            return !path.contains("*") && !path.contains("?") && path != "/"
        })
        XCTAssertTrue(CleanupPlanner.plan(manifest: manifest).dryRun)
    }

    func testFakeLoginManagerDoesNotTouchSystemRegistration() async throws {
        try await MainActor.run {
            let manager = FakeLoginItemManager()
            XCTAssertFalse(manager.isEnabled)
            try manager.setEnabled(true)
            XCTAssertTrue(manager.isEnabled)
            try manager.setEnabled(false)
            XCTAssertFalse(manager.isEnabled)
        }
    }

    func testDeterministic24HourSimulation() async {
        let report = await DeterministicSimulation.run24Hours()
        XCTAssertTrue(report.passed, String(describing: report))
        XCTAssertEqual(report.ticks, 86_400)
        XCTAssertEqual(report.invalidDutyCount, 0)
        XCTAssertEqual(report.unhandledErrorCount, 0)
        XCTAssertLessThanOrEqual(report.maxEventLogSize, 128)
        XCTAssertLessThanOrEqual(report.maxDeviceLogSize, 512)
        XCTAssertFalse(report.commandFlood)
        XCTAssertFalse(report.endlessReconnect)
        XCTAssertFalse(report.deadlock)
    }
}
