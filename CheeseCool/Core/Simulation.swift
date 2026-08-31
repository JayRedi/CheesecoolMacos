import Foundation

public struct SimulationReport: Codable, Equatable, Sendable {
    public let durationSeconds: Int
    public let ticks: Int
    public let totalDeviceCommands: Int
    public let connectAttempts: Int
    public let maxEventLogSize: Int
    public let maxDeviceLogSize: Int
    public let invalidDutyCount: Int
    public let unhandledErrorCount: Int
    public let finalControlState: ControlState
    public let finalConnectionState: ConnectionState
    public let commandFlood: Bool
    public let deadlock: Bool
    public let endlessReconnect: Bool
    public let passed: Bool
}

public enum DeterministicSimulation {
    public static func run24Hours() async -> SimulationReport {
        let duration = 24 * 60 * 60
        let configuration = (try? Configuration(
            reconnectPolicy: ReconnectPolicy(
                maxAttempts: 3,
                initialDelay: 1,
                backoffMultiplier: 2,
                maxDelay: 4
            )
        )) ?? .defaults
        let clock = ManualClock()
        let source = FakeSensorProvider(temperature: 45)
        let device = FakeHostDevice(clock: clock)
        let events = EventLog(capacity: 128)
        let session = ControlSession(
            temperatureSource: source,
            device: device,
            configuration: configuration,
            clock: clock,
            eventLog: events
        )

        var invalidDuties = 0
        var errors = 0
        var maxEvents = 0
        var maxDeviceLog = 0
        let disconnectWindows = [(10_000, 10_010), (45_000, 45_008), (75_000, 75_012)]

        for second in 0..<duration {
            await source.setTemperature(62.5 + 27.5 * sin(Double(second) / 1_800))
            for (start, end) in disconnectWindows {
                if second == start {
                    await device.setUSBAvailable(false)
                } else if second == end {
                    await device.setUSBAvailable(true)
                    await session.requestReconnect()
                }
            }
            if (20_000..<20_006).contains(second) || (65_000..<65_035).contains(second) {
                await source.setUnavailable()
            }

            switch second {
            case 30_000, 55_000:
                await session.prepareForSleep()
            case 30_040, 55_025:
                await session.resumeFromSleep()
            case 40_000:
                await device.setPowerFault(true)
            case 40_010:
                await device.setPowerFault(false)
                await session.acknowledgePowerFault()
            case 50_000:
                await device.injectCommandFailure()
                try? await session.setMode(.manual, manualDuty: 53)
            case 50_010:
                await session.requestReconnect()
                try? await session.setMode(.auto)
            case 60_000:
                await device.reboot()
                await session.requestReconnect()
            case 70_000:
                try? await session.setMode(.max)
            case 70_100:
                try? await session.setMode(.auto)
            case 80_000:
                try? await session.applyConfiguration(configuration)
            default:
                break
            }

            _ = await session.tick()
            let status = await device.peekStatus()
            if !(0...100).contains(status.actualDuty) || !(0...100).contains(status.targetDuty) {
                invalidDuties += 1
            }
            maxEvents = max(maxEvents, await events.count)
            maxDeviceLog = max(maxDeviceLog, await device.commandHistory().count)
            do { try clock.advance(by: 1) }
            catch { errors += 1 }
        }

        let totalCommands = await device.totalCommandCount
        let attempts = await device.connectAttempts
        let finalControl = await session.currentControlState
        let finalConnection = await session.currentConnectionState
        let commandFlood = totalCommands > duration / Int(configuration.keepaliveInterval) + 500
        let endlessReconnect = attempts >= 30
        let deadlock = [.deviceUnavailable, .powerFault, .stopped].contains(finalControl)
            || finalConnection != .connected
        let passed = invalidDuties == 0
            && errors == 0
            && !commandFlood
            && !endlessReconnect
            && !deadlock

        return SimulationReport(
            durationSeconds: duration,
            ticks: duration,
            totalDeviceCommands: totalCommands,
            connectAttempts: attempts,
            maxEventLogSize: maxEvents,
            maxDeviceLogSize: maxDeviceLog,
            invalidDutyCount: invalidDuties,
            unhandledErrorCount: errors,
            finalControlState: finalControl,
            finalConnectionState: finalConnection,
            commandFlood: commandFlood,
            deadlock: deadlock,
            endlessReconnect: endlessReconnect,
            passed: passed
        )
    }
}
