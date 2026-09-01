import CheeseCoolCore
import Foundation

@main
struct HardwareValidationHarness {
    static func main() async {
        do {
            try await run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("Hardware validation failed: \(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func run(arguments: [String]) async throws {
        guard let command = arguments.first else { throw HarnessError.usage }
        switch command {
        case "discover", "status":
            let device = makeDevice()
            defer { Task { await device.close() } }
            try await device.connect()
            try printStatus(await device.getStatus(), diagnostics: await device.diagnostics())
        case "manual":
            guard arguments.count == 2, let duty = Int(arguments[1]), (0...100).contains(duty) else {
                throw HarnessError.usage
            }
            let device = makeDevice()
            let session = makeSession(device: device)
            try await session.setMode(.manual, manualDuty: duty)
            let telemetry = await session.tick()
            try requireConnected(telemetry)
            try await Task.sleep(for: .seconds(5))
            try printStatus(await device.getStatus(), telemetry: telemetry, diagnostics: await device.diagnostics())
            await session.stop()
        case "max":
            let device = makeDevice()
            let session = makeSession(device: device)
            try await session.setMode(.max)
            let telemetry = await session.tick()
            try requireConnected(telemetry)
            try await Task.sleep(for: .seconds(5))
            try printStatus(await device.getStatus(), telemetry: telemetry, diagnostics: await device.diagnostics())
            await session.stop()
        case "auto-soak":
            guard arguments.count == 2, let seconds = Int(arguments[1]), seconds > 0 else {
                throw HarnessError.usage
            }
            try await autoSoak(seconds: seconds)
        case "failsafe-test":
            try await failsafeTest()
        case "reconnect-watch":
            guard arguments.count == 2, let cycles = Int(arguments[1]), cycles > 0 else {
                throw HarnessError.usage
            }
            try await reconnectWatch(cycles: cycles)
        default:
            throw HarnessError.usage
        }
    }

    private static func makeDevice() -> HIDHostDevice {
        let discovery = HIDDeviceDiscovery()
        return HIDHostDevice(
            discovery: discovery,
            transport: NativeHIDTransport(discovery: discovery)
        )
    }

    private static func makeSession(device: HIDHostDevice) -> ControlSession {
        ControlSession(temperatureSource: AppleSiliconTemperatureProvider(), device: device)
    }

    private static func autoSoak(seconds: Int) async throws {
        let device = makeDevice()
        let session = makeSession(device: device)
        defer { Task { await session.stop() } }
        let started = Date()
        var elapsed = 0
        while elapsed < seconds {
            let telemetry = await session.tick()
            try requireConnected(telemetry)
            guard telemetry.temperatureValid else { throw HarnessError.invalidTemperature }
            printTelemetry(telemetry, diagnostics: await device.diagnostics())
            let delay = min(5, seconds - elapsed)
            try await Task.sleep(for: .seconds(delay))
            elapsed = Int(Date().timeIntervalSince(started))
        }
    }

    private static func failsafeTest() async throws {
        let device = makeDevice()
        let session = makeSession(device: device)
        try await session.setMode(.manual, manualDuty: 20)
        let before = await session.tick()
        try requireConnected(before)
        let initial = try await device.getStatus()
        guard initial.targetDuty == 20, !initial.failsafe else { throw HarnessError.unexpectedStatus }
        await session.stop()

        // The session is closed before this delay: no Protocol V1 traffic originates here.
        try await Task.sleep(for: .seconds(31))

        let reader = makeDevice()
        try await reader.connect()
        let failedSafe = try await reader.getStatus()
        try printStatus(failedSafe, diagnostics: await reader.diagnostics())
        // A fresh HIDHostDevice connection starts with PING. The frozen firmware
        // treats that as valid host activity and may clear the failsafe flag before
        // GET_STATUS can read it; the independently observable failsafe output is
        // nevertheless its fixed 50% duty.
        guard failedSafe.targetDuty == 50 else { throw HarnessError.failsafeDidNotActivate }
        await reader.close()

        let reclaimer = makeDevice()
        let reclaimSession = makeSession(device: reclaimer)
        try await reclaimSession.setMode(.manual, manualDuty: 20)
        let reclaimed = await reclaimSession.tick()
        try requireConnected(reclaimed)
        let recovered = try await reclaimer.getStatus()
        try printStatus(recovered, telemetry: reclaimed, diagnostics: await reclaimer.diagnostics())
        guard !recovered.failsafe, recovered.targetDuty == 20 else { throw HarnessError.reclaimFailed }
        await reclaimSession.stop()
    }

    private static func reconnectWatch(cycles: Int) async throws {
        let device = makeDevice()
        defer { Task { await device.close() } }
        try await device.connect()
        _ = try await device.getStatus()
        for cycle in 1...cycles {
            print("PHYSICAL ACTION REQUIRED: Unplug the CheeseCool USB cable for reconnect cycle \(cycle)/\(cycles).")
            try await waitForDevice(device, present: false, timeout: 90)
            print("Device removal observed. Reconnect the CheeseCool USB cable now.")
            try await waitForDevice(device, present: true, timeout: 90)
            await device.disconnect()
            try await device.connect()
            try printStatus(await device.getStatus(), diagnostics: await device.diagnostics())
        }
    }

    private static func waitForDevice(_ device: HIDHostDevice, present: Bool, timeout: Int) async throws {
        for _ in 0..<timeout {
            let matching = await device.diagnostics().matchingDevices
            if (!matching.isEmpty) == present { return }
            try await Task.sleep(for: .seconds(1))
        }
        throw HarnessError.reconnectTimeout
    }

    private static func requireConnected(_ telemetry: TelemetrySnapshot) throws {
        guard telemetry.connectionState == .connected, telemetry.lastError == nil else {
            throw HarnessError.controlUnavailable
        }
    }

    private static func printStatus(
        _ status: DeviceStatus,
        telemetry: TelemetrySnapshot? = nil,
        diagnostics: HIDDiagnosticsSnapshot
    ) throws {
        let output = ValidationOutput(status: status, telemetry: telemetry, diagnostics: diagnostics)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(output), as: UTF8.self))
    }

    private static func printTelemetry(_ telemetry: TelemetrySnapshot, diagnostics: HIDDiagnosticsSnapshot) {
        let output = SoakOutput(telemetry: telemetry, diagnostics: diagnostics)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        print((try? String(decoding: encoder.encode(output), as: UTF8.self)) ?? "{\"error\":\"encode\"}")
    }
}

private struct ValidationOutput: Encodable {
    let status: DeviceStatus
    let telemetry: TelemetrySnapshot?
    let diagnostics: DiagnosticsOutput

    init(status: DeviceStatus, telemetry: TelemetrySnapshot?, diagnostics: HIDDiagnosticsSnapshot) {
        self.status = status
        self.telemetry = telemetry
        self.diagnostics = DiagnosticsOutput(diagnostics)
    }
}

private struct SoakOutput: Encodable {
    let timestamp: Date = Date()
    let telemetry: TelemetrySnapshot
    let diagnostics: DiagnosticsOutput

    init(telemetry: TelemetrySnapshot, diagnostics: HIDDiagnosticsSnapshot) {
        self.telemetry = telemetry
        self.diagnostics = DiagnosticsOutput(diagnostics)
    }
}

private struct DiagnosticsOutput: Encodable {
    let matchingDeviceCount: Int
    let connected: Bool
    let lastCommand: String?
    let lastSequence: UInt8?
    let lastRoundTripMilliseconds: Double?
    let lastError: String?
    let disconnectCount: Int
    let reconnectCount: Int

    init(_ diagnostics: HIDDiagnosticsSnapshot) {
        matchingDeviceCount = diagnostics.matchingDevices.count
        connected = diagnostics.connected
        lastCommand = diagnostics.lastCommand.map { String(describing: $0).uppercased() }
        lastSequence = diagnostics.lastSequence
        lastRoundTripMilliseconds = diagnostics.lastRoundTripMilliseconds
        lastError = diagnostics.lastError
        disconnectCount = diagnostics.disconnectCount
        reconnectCount = diagnostics.reconnectCount
    }
}

private enum HarnessError: LocalizedError {
    case usage, controlUnavailable, invalidTemperature, unexpectedStatus, failsafeDidNotActivate, reclaimFailed, reconnectTimeout

    var errorDescription: String? {
        switch self {
        case .usage: return "Usage: discover | status | manual <0...100> | max | auto-soak <seconds> | failsafe-test | reconnect-watch <cycles>"
        case .controlUnavailable: return "Production ControlSession did not establish a healthy real-device connection"
        case .invalidTemperature: return "Apple Silicon PMU/PMU2 temperature sample is unavailable"
        case .unexpectedStatus: return "Unexpected pre-failsafe device status"
        case .failsafeDidNotActivate: return "MCU failsafe did not report duty 50 after 31 seconds without traffic"
        case .reclaimFailed: return "Production ControlSession could not reclaim control after failsafe"
        case .reconnectTimeout: return "Timed out waiting for physical device transition"
        }
    }
}
