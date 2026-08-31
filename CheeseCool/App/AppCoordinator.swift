import AppKit
import CheeseCoolCore

@MainActor
public final class AppCoordinator {
    private let clock = SystemMonotonicClock()
    private let simulationDevice: FakeHostDevice?
    private let hidDevice: HIDHostDevice?
    private let eventLog: EventLog
    private let controlSession: ControlSession
    private let lifecycleManager: LifecycleManager
    private let sensorEngine: SensorEngine
    private let configStore: ConfigStore
    private let telemetryStore = TelemetryStore()
    private let loginItemManager: any LoginItemManaging
    private var controlTask: Task<Void, Never>?
    private var settingsSaveTask: Task<Void, Never>?
    private var lastAppliedConfiguration: Configuration

    private let settingsViewModel: SettingsViewModel
    private let settingsCoordinator: SettingsCoordinator
    private let menuBarManager: MenuBarManager
    private var lifecycleRouter: LifecycleNotificationRouter?

    public init(
        loginItemManager: (any LoginItemManaging)? = nil,
        simulationMode: Bool = false
    ) {
        let resolvedLoginItemManager = loginItemManager ?? SMAppServiceLoginItemManager()
        var configuration = Configuration.defaults
        configuration.launchAtLogin = resolvedLoginItemManager.isEnabled
        let configurationURL = ConfigStore.productionURL()
        let temperatureProvider = AppleSiliconTemperatureProvider()
        let resolvedDevice: any HostDevice
        let simulationDevice: FakeHostDevice?
        let hidDevice: HIDHostDevice?
        if simulationMode {
            let fakeDevice = FakeHostDevice(clock: clock)
            resolvedDevice = fakeDevice
            simulationDevice = fakeDevice
            hidDevice = nil
        } else {
            let discovery = HIDDeviceDiscovery()
            let transport = NativeHIDTransport(discovery: discovery)
            let nativeDevice = HIDHostDevice(discovery: discovery, transport: transport)
            resolvedDevice = nativeDevice
            simulationDevice = nil
            hidDevice = nativeDevice
        }
        let eventLog = EventLog(capacity: 128)
        let session = ControlSession(
            temperatureSource: temperatureProvider,
            device: resolvedDevice,
            configuration: configuration,
            clock: clock,
            eventLog: eventLog
        )
        self.simulationDevice = simulationDevice
        self.hidDevice = hidDevice
        self.eventLog = eventLog
        self.controlSession = session
        self.lifecycleManager = LifecycleManager(controlSession: session)
        self.sensorEngine = SensorEngine(
            temperatureProvider: temperatureProvider,
            cpuProvider: MachCPULoadProvider(),
            powerProvider: UnsupportedSoCPowerProvider(),
            gpuProvider: UnsupportedGPULoadProvider(),
            clock: clock
        )
        self.configStore = ConfigStore(
            fileURL: configurationURL,
            legacyFileURL: ConfigStore.legacyProductionURL()
        )
        let settingsViewModel = SettingsViewModel(
            configuration: configuration,
            simulationMode: simulationMode
        )
        self.settingsViewModel = settingsViewModel
        self.settingsCoordinator = SettingsCoordinator(model: settingsViewModel)
        self.menuBarManager = MenuBarManager()
        self.loginItemManager = resolvedLoginItemManager
        self.lastAppliedConfiguration = configuration
        wireSettingsActions()
        wireMenuBarActions()
    }

    public func start() {
        menuBarManager.apply(preferences: settingsViewModel.configuration.menuBar)
        loadConfiguration()
        startLifecycleNotifications()
        startControlLoop()
    }

    public func runDryRun(
        duration: TimeInterval,
        interval: TimeInterval = 1
    ) async -> DryRunReport {
        precondition(duration > 0 && interval > 0)
        let wallStart = Date()
        let start = clock.now
        var nextSampleTime = start
        var samples: [DryRunSample] = []
        while clock.now - start < duration, !Task.isCancelled {
            let metrics = await sensorEngine.poll()
            let telemetry = await controlSession.tick()
            samples.append(DryRunSample(
                elapsedSeconds: clock.now - start,
                temperatureCelsius: telemetry.socTemperatureCelsius,
                temperatureState: telemetry.temperatureState,
                temperatureValid: telemetry.temperatureValid,
                rawAutoDuty: telemetry.rawAutoDuty,
                requestedDuty: telemetry.requestedDuty,
                fakeDeviceDuty: telemetry.deviceActualDuty,
                fakeRPM: telemetry.rpm,
                cpuLoadPercent: metrics.cpuLoadPercent,
                socPowerWatts: metrics.socPowerWatts,
                gpuLoadPercent: metrics.gpuLoadPercent,
                temperatureLatencyMilliseconds: metrics.socTemperature.latencyMilliseconds,
                cpuLatencyMilliseconds: metrics.cpuLoad.latencyMilliseconds,
                error: telemetry.lastError
            ))
            nextSampleTime += interval
            let remaining = duration - (clock.now - start)
            let delay = min(remaining, nextSampleTime - clock.now)
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
        }
        let commandCount: Int
        if let simulationDevice {
            commandCount = await simulationDevice.totalCommandCount
        } else {
            commandCount = 0
        }
        await lifecycleManager.stop()
        return DryRunReport(
            startedAt: wallStart,
            requestedDurationSeconds: duration,
            actualDurationSeconds: clock.now - start,
            samplingIntervalSeconds: interval,
            samples: samples,
            commandCount: commandCount
        )
    }

#if DEBUG
    func showSettingsForUITesting() {
        settingsCoordinator.show(initialTab: .fan)
    }
#endif

    public func stop() async {
        controlTask?.cancel()
        controlTask = nil
        settingsSaveTask?.cancel()
        settingsSaveTask = nil
        lifecycleRouter?.stop()
        lifecycleRouter = nil
        do {
            try settingsViewModel.configuration.validate()
            try await configStore.save(settingsViewModel.configuration)
        } catch {
            await eventLog.append(
                timestamp: clock.now,
                type: .configurationError,
                detail: "Quit-time configuration flush failed: \(error.localizedDescription)"
            )
        }
        await lifecycleManager.stop()
    }

    private func wireSettingsActions() {
        settingsViewModel.onConfigurationChanged = { [weak self] configuration in
            self?.configurationChanged(configuration)
        }
        settingsViewModel.onReset = { [weak self] in self?.resetConfiguration() }
        settingsViewModel.onClearLogs = { [weak self] in
            guard let self else { return }
            Task { await self.eventLog.clear() }
        }
    }

    private func wireMenuBarActions() {
        menuBarManager.onSettings = { [weak self] in self?.settingsCoordinator.show() }
        menuBarManager.onQuit = { NSApp.terminate(nil) }
        menuBarManager.onModeSelected = { [weak self] mode in
            self?.settingsViewModel.configuration.operatingMode = mode
        }
        menuBarManager.onMetricVisibilityChanged = { [weak self] metric, visible in
            self?.settingsViewModel.setMetric(metric, visible: visible)
        }
    }

    private func startControlLoop() {
        controlTask?.cancel()
        controlTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let cycleStart = clock.now
                let metrics = await sensorEngine.poll()
                let telemetry = await controlSession.tick()
                telemetryStore.publish(telemetry)
                telemetryStore.publish(metrics: metrics)
                settingsViewModel.update(metrics: metrics)
                settingsViewModel.update(telemetry: telemetry)
                if let hidDevice {
                    settingsViewModel.update(hidDiagnostics: await hidDevice.diagnostics())
                }
                menuBarManager.update(telemetry: telemetry, metrics: metrics)
                let interval = settingsViewModel.configuration.refreshInterval
                let delay = max(0, interval - (clock.now - cycleStart))
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    private func loadConfiguration() {
        Task { [weak self] in
            guard let self else { return }
            let result = await configStore.load()
            var configuration = result.configuration
            configuration.launchAtLogin = loginItemManager.isEnabled
            await apply(configuration)
            try? await configStore.save(configuration)
            if let error = result.error {
                await eventLog.append(
                    timestamp: clock.now,
                    type: .configurationError,
                    detail: error
                )
            }
        }
    }

    private func resetConfiguration() {
        Task { [weak self] in
            guard let self else { return }
            do {
                var configuration = Configuration.defaults
                try loginItemManager.setEnabled(configuration.launchAtLogin)
                configuration.launchAtLogin = loginItemManager.isEnabled
                try await configStore.save(configuration)
                await apply(configuration)
            } catch {
                await eventLog.append(
                    timestamp: clock.now,
                    type: .configurationError,
                    detail: error.localizedDescription
                )
            }
        }
    }

    private func configurationChanged(_ configuration: Configuration) {
        do {
            try configuration.validate()
            if configuration.launchAtLogin != loginItemManager.isEnabled {
                try loginItemManager.setEnabled(configuration.launchAtLogin)
            }
        } catch {
            var restored = lastAppliedConfiguration
            restored.launchAtLogin = loginItemManager.isEnabled
            settingsViewModel.replaceConfiguration(restored)
            Task { await eventLog.append(
                timestamp: clock.now,
                type: .configurationError,
                detail: error.localizedDescription
            ) }
            return
        }

        Task { [weak self] in
            guard let self else { return }
            await apply(configuration)
        }
        settingsSaveTask?.cancel()
        settingsSaveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            do {
                try await configStore.save(configuration)
            } catch {
                await eventLog.append(timestamp: clock.now, type: .configurationError, detail: error.localizedDescription)
            }
        }
    }

    private func apply(_ configuration: Configuration) async {
        settingsViewModel.replaceConfiguration(configuration)
        menuBarManager.apply(preferences: configuration.menuBar)
        try? await controlSession.applyConfiguration(configuration)
        try? await controlSession.setMode(configuration.operatingMode, manualDuty: configuration.manualDuty)
        lastAppliedConfiguration = configuration
    }

    private func startLifecycleNotifications() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        lifecycleRouter = LifecycleNotificationRouter(
            notificationCenter: notificationCenter,
            sleepNotification: NSWorkspace.willSleepNotification,
            wakeNotification: NSWorkspace.didWakeNotification,
            onSleep: { [weak self] in
                guard let self else { return }
                Task { await self.lifecycleManager.prepareForSleep() }
            },
            onWake: { [weak self] in
                guard let self else { return }
                Task { await self.lifecycleManager.resumeFromSleep() }
            }
        )
        lifecycleRouter?.start()
    }
}
