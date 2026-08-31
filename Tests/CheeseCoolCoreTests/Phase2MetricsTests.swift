import Foundation
import XCTest
@testable import CheeseCoolCore

final class Phase2MetricsTests: XCTestCase {
    private actor TemperatureScript: TemperatureSensorReadingSource {
        private var values: [[RawTemperatureSensor]]
        init(_ values: [[RawTemperatureSensor]]) { self.values = values }
        func readSensors() async throws -> [RawTemperatureSensor] {
            if values.count > 1 { return values.removeFirst() }
            return values.first ?? []
        }
    }

    private final class TickScript: CPUTickSource, @unchecked Sendable {
        private let lock = NSLock()
        private var values: [CPUTickSnapshot]
        init(_ values: [CPUTickSnapshot]) { self.values = values }
        func readTicks() throws -> CPUTickSnapshot {
            lock.lock()
            defer { lock.unlock() }
            guard !values.isEmpty else { throw SensorError.unavailable }
            return values.count == 1 ? values[0] : values.removeFirst()
        }
    }

    private struct FixedProvider: SoCTemperatureProviding, CPULoadProviding,
        PowerProviding, GPULoadProviding {
        let temperature: MetricSample
        let cpu: MetricSample
        let power: MetricSample
        let gpu: MetricSample
        func readSoCTemperature(now: TimeInterval) async -> MetricSample { temperature }
        func readCPULoad(now: TimeInterval) async -> MetricSample { cpu }
        func readSoCPower(now: TimeInterval) async -> MetricSample { power }
        func readGPULoad(now: TimeInterval) async -> MetricSample { gpu }
    }

    func testTemperatureSensorNameFilteringIsStrict() {
        XCTAssertTrue(AppleHIDTemperatureSensorSource.isSoCDieSensor("PMU tdie1"))
        XCTAssertTrue(AppleHIDTemperatureSensorSource.isSoCDieSensor("PMU2 tdie14"))
        for excluded in ["PMU tdev1", "PMU2 tcal", "NAND temp", "Battery", "GPU MTR Temp Sensor"] {
            XCTAssertFalse(AppleHIDTemperatureSensorSource.isSoCDieSensor(excluded))
        }
    }

    func testTemperatureUsesMaximumValidSoCDieValueAndRejectsInvalidValues() async {
        let source = TemperatureScript([[
            .init(name: "PMU tdie1", celsius: 54),
            .init(name: "PMU2 tdie2", celsius: 67.5),
            .init(name: "PMU tdie3", celsius: .nan),
            .init(name: "PMU tdie4", celsius: 126),
            .init(name: "PMU tdev1", celsius: 90)
        ]])
        let provider = AppleSiliconTemperatureProvider(source: source)
        let sample = await provider.readTemperature(now: 10)
        XCTAssertTrue(sample.valid)
        XCTAssertEqual(sample.controlTemperatureCelsius, 67.5)
        XCTAssertEqual(sample.sensorCount, 2)
        XCTAssertEqual(sample.state, .warm)
    }

    func testTemperatureBecomesStaleAfterFiveSeconds() async {
        let source = TemperatureScript([
            [.init(name: "PMU tdie1", celsius: 50)],
            [],
            []
        ])
        let provider = AppleSiliconTemperatureProvider(source: source)
        let initial = await provider.readTemperature(now: 0)
        let withinThreshold = await provider.readTemperature(now: 5)
        XCTAssertTrue(initial.valid)
        XCTAssertTrue(withinThreshold.valid)
        let stale = await provider.readTemperature(now: 5.001)
        XCTAssertFalse(stale.valid)
        XCTAssertEqual(stale.state, .unknown)
        XCTAssertEqual(stale.sourceStatus, .stale)
    }

    func testCPUUsesDeltasIncludingUserSystemAndNice() async {
        let provider = MachCPULoadProvider(source: TickScript([
            .init(user: 100, system: 50, nice: 10, idle: 840),
            .init(user: 120, system: 60, nice: 15, idle: 865)
        ]))
        let first = await provider.readCPULoad(now: 0)
        XCTAssertFalse(first.valid)
        let second = await provider.readCPULoad(now: 1)
        XCTAssertTrue(second.valid)
        XCTAssertEqual(second.value ?? -1, 58.333_333_333_3, accuracy: 0.000_001)
    }

    func testCPUCounterResetIsUnavailable() async {
        let provider = MachCPULoadProvider(source: TickScript([
            .init(user: 100, system: 50, nice: 10, idle: 840),
            .init(user: 90, system: 60, nice: 15, idle: 900)
        ]))
        _ = await provider.readCPULoad(now: 0)
        let reset = await provider.readCPULoad(now: 1)
        XCTAssertFalse(reset.valid)
        XCTAssertEqual(reset.sourceStatus, .unavailable)
    }

    func testUnsupportedPowerAndGPUAreExplicit() async {
        let power = UnsupportedSoCPowerProvider().readSoCPower(now: 1)
        let gpu = UnsupportedGPULoadProvider().readGPULoad(now: 1)
        XCTAssertEqual(power.sourceStatus, .unsupported)
        XCTAssertEqual(gpu.sourceStatus, .unsupported)
        XCTAssertNil(power.value)
        XCTAssertNil(gpu.value)
    }

    func testSensorEngineIsolatesProviderFailures() async {
        let now = 7.0
        let fixed = FixedProvider(
            temperature: .valid(42, timestamp: now, source: "test"),
            cpu: .valid(18, timestamp: now, source: "test"),
            power: .unavailable(timestamp: now, source: "test", reason: "failure"),
            gpu: .unavailable(timestamp: now, source: "test", status: .unsupported, reason: "unsupported")
        )
        let engine = SensorEngine(
            temperatureProvider: fixed,
            cpuProvider: fixed,
            powerProvider: fixed,
            gpuProvider: fixed,
            clock: ManualClock(now: now)
        )
        let snapshot = await engine.poll()
        XCTAssertEqual(snapshot.socTemperatureCelsius, 42)
        XCTAssertEqual(snapshot.cpuLoadPercent, 18)
        XCTAssertNil(snapshot.socPowerWatts)
        XCTAssertEqual(snapshot.gpuLoad.sourceStatus, .unsupported)
    }

    func testUnsupportedMetricIsRemovedWithoutHidingTransientFailure() {
        let now = 1.0
        let snapshot = MetricsSnapshot(
            timestamp: now,
            socTemperature: .unavailable(timestamp: now, source: "test", reason: "temporary"),
            cpuLoad: .valid(10, timestamp: now, source: "test"),
            socPower: .unavailable(timestamp: now, source: "test", status: .unsupported, reason: "unsupported"),
            gpuLoad: .unavailable(timestamp: now, source: "test", status: .unsupported, reason: "unsupported")
        )
        XCTAssertEqual(
            MetricAvailabilityPolicy.unsupportedMetrics(in: snapshot),
            [.socPower, .gpuLoad]
        )
    }

    func testInjectedRealTemperaturePipelineDrivesAutoAndFakeHostOnly() async {
        let clock = ManualClock()
        let provider = AppleSiliconTemperatureProvider(source: TemperatureScript([[
            .init(name: "PMU tdie1", celsius: 70)
        ]]))
        let device = FakeHostDevice(clock: clock)
        let session = ControlSession(temperatureSource: provider, device: device, clock: clock)
        let telemetry = await session.tick()
        XCTAssertTrue(telemetry.temperatureValid)
        XCTAssertEqual(telemetry.socTemperatureCelsius, 70)
        XCTAssertEqual(telemetry.rawAutoDuty, 60)
        XCTAssertEqual(telemetry.deviceActualDuty, telemetry.requestedDuty)
    }

    func testInformationMetricFailureDoesNotAffectAutoSafety() async {
        let clock = ManualClock()
        let temperature = FakeSensorProvider(temperature: 60)
        let device = FakeHostDevice(clock: clock)
        let session = ControlSession(temperatureSource: temperature, device: device, clock: clock)
        let failing = FixedProvider(
            temperature: .valid(60, timestamp: 0, source: "test"),
            cpu: .unavailable(timestamp: 0, source: "test", reason: "cpu"),
            power: .unavailable(timestamp: 0, source: "test", reason: "power"),
            gpu: .unavailable(timestamp: 0, source: "test", reason: "gpu")
        )
        let engine = SensorEngine(
            temperatureProvider: failing,
            cpuProvider: failing,
            powerProvider: failing,
            gpuProvider: failing,
            clock: clock
        )
        _ = await engine.poll()
        let telemetry = await session.tick()
        XCTAssertTrue(telemetry.temperatureValid)
        XCTAssertEqual(telemetry.controlState, .autoActive)
        XCTAssertEqual(telemetry.connectionState, .connected)
    }

    func testSettingsMigrationPreservesValuesAndRunsOnlyOnce() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = directory.appendingPathComponent("config.json")
        let settings = directory.appendingPathComponent("settings.json")
        var original = Configuration.defaults
        original.manualDuty = 73
        original.menuBar.visibleMetrics = [.socTemperature, .cpuLoad]
        original.menuBar.metricOrder = [.cpuLoad, .socTemperature, .fanRPM, .fanDuty, .socPower, .gpuLoad]
        original.refreshInterval = 2
        try original.encoded().write(to: legacy)

        let store = ConfigStore(fileURL: settings, legacyFileURL: legacy)
        let migrated = await store.load()
        XCTAssertEqual(migrated.configuration, original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: settings.path))

        var changedLegacy = original
        changedLegacy.manualDuty = 12
        try changedLegacy.encoded().write(to: legacy)
        let secondLaunch = await store.load()
        XCTAssertEqual(secondLaunch.configuration.manualDuty, 73)
    }

    func testSettingsRoundTripPreservesPhase2AcceptanceFields() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = directory.appendingPathComponent("settings.json")
        var expected = Configuration.defaults
        expected.manualDuty = 64
        expected.autoCurve = [
            .init(temperatureCelsius: 35, duty: 5),
            .init(temperatureCelsius: 75, duty: 70),
            .init(temperatureCelsius: 90, duty: 100)
        ]
        expected.deadband = 3
        expected.rampUpPerSecond = 15
        expected.rampDownPerSecond = 7
        expected.refreshInterval = 5
        expected.menuBar.mainIconPreferredVisible = false
        expected.menuBar.visibleMetrics = [.cpuLoad, .socTemperature]
        expected.menuBar.metricOrder = [.socTemperature, .cpuLoad, .fanRPM, .fanDuty, .socPower, .gpuLoad]
        let store = ConfigStore(fileURL: settings)
        try await store.save(expected)
        let loaded = await store.load()
        XCTAssertEqual(loaded.configuration, expected)
    }

    func testCorruptLegacySettingsFallsBackOnceWithoutRepeatedMigration() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = directory.appendingPathComponent("config.json")
        let settings = directory.appendingPathComponent("settings.json")
        try Data("{broken".utf8).write(to: legacy)
        let store = ConfigStore(fileURL: settings, legacyFileURL: legacy)
        let first = await store.load()
        XCTAssertTrue(first.usedDefaults)
        XCTAssertNotNil(first.error)
        XCTAssertTrue(FileManager.default.fileExists(atPath: settings.path))

        var laterLegacy = Configuration.defaults
        laterLegacy.manualDuty = 88
        try laterLegacy.encoded().write(to: legacy)
        let second = await store.load()
        XCTAssertEqual(second.configuration, .defaults)
        XCTAssertNil(second.error)
    }

    func testAllMetricsCanBeUnavailableWithoutLosingTypedState() async {
        let unavailable = MetricSample.unavailable(
            timestamp: 1,
            source: "test",
            reason: "injected"
        )
        let fixed = FixedProvider(
            temperature: unavailable,
            cpu: unavailable,
            power: unavailable,
            gpu: unavailable
        )
        let engine = SensorEngine(
            temperatureProvider: fixed,
            cpuProvider: fixed,
            powerProvider: fixed,
            gpuProvider: fixed,
            clock: ManualClock(now: 1)
        )
        let snapshot = await engine.poll()
        XCTAssertFalse(snapshot.socTemperature.valid)
        XCTAssertFalse(snapshot.cpuLoad.valid)
        XCTAssertFalse(snapshot.socPower.valid)
        XCTAssertFalse(snapshot.gpuLoad.valid)
    }

    func testRefreshIntervalIsConstrained() {
        XCTAssertNoThrow(try Configuration(refreshInterval: 1))
        XCTAssertNoThrow(try Configuration(refreshInterval: 2))
        XCTAssertNoThrow(try Configuration(refreshInterval: 5))
        XCTAssertThrowsError(try Configuration(refreshInterval: 0.001))
        XCTAssertThrowsError(try Configuration(refreshInterval: 10))
    }
}
