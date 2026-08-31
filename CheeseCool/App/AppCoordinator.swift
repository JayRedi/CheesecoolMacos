import AppKit
import CheeseCoolCore

@MainActor
public final class AppCoordinator {
    private let clock = SystemMonotonicClock()
    private let sensorProvider: FakeSensorProvider
    private let device: FakeHostDevice
    private let eventLog: EventLog
    private let controlSession: ControlSession
    private let lifecycleManager: LifecycleManager
    private let sensorEngine: SensorEngine
    private let configStore: ConfigStore
    private let telemetryStore = TelemetryStore()
    private let loginItemManager: any LoginItemManaging
    private var controlTask: Task<Void, Never>?

    private let settingsViewModel: SettingsViewModel
    private let settingsCoordinator: SettingsCoordinator
    private let menuBarManager: MenuBarManager

    public init(loginItemManager: (any LoginItemManaging)? = nil) {
        let configuration = Configuration.defaults
        let configurationURL = ConfigStore.productionURL()
        let sensorProvider = FakeSensorProvider()
        let device = FakeHostDevice(clock: clock)
        let eventLog = EventLog(capacity: 128)
        let session = ControlSession(
            temperatureSource: sensorProvider,
            device: device,
            configuration: configuration,
            clock: clock,
            eventLog: eventLog
        )
        self.sensorProvider = sensorProvider
        self.device = device
        self.eventLog = eventLog
        self.controlSession = session
        self.lifecycleManager = LifecycleManager(controlSession: session)
        self.sensorEngine = SensorEngine(
            temperatureProvider: sensorProvider,
            cpuProvider: sensorProvider,
            powerProvider: sensorProvider,
            gpuProvider: sensorProvider,
            clock: clock
        )
        self.configStore = ConfigStore(fileURL: configurationURL)
        let settingsViewModel = SettingsViewModel(
            configuration: configuration,
            configurationURL: configurationURL
        )
        self.settingsViewModel = settingsViewModel
        self.settingsCoordinator = SettingsCoordinator(model: settingsViewModel)
        self.menuBarManager = MenuBarManager()
        self.loginItemManager = loginItemManager ?? SMAppServiceLoginItemManager()
        wireSettingsActions()
        wireMenuBarActions()
    }

    public func start() {
        menuBarManager.apply(preferences: settingsViewModel.configuration.menuBar)
        reloadConfiguration()
        startControlLoop()
    }

    public func stop() async {
        controlTask?.cancel()
        controlTask = nil
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
        settingsViewModel.onSave = { [weak self] configuration in
            self?.save(configuration)
        }
        settingsViewModel.onReload = { [weak self] in self?.reloadConfiguration() }
        settingsViewModel.onReset = { [weak self] in self?.resetConfiguration() }
        settingsViewModel.onClearLogs = { [weak self] in
            guard let self else { return }
            Task { await self.eventLog.clear() }
        }
    }

    private func wireMenuBarActions() {
        menuBarManager.onModeSelected = { [weak self] mode in
            guard let self else { return }
            Task { try? await self.controlSession.setMode(mode) }
        }
        menuBarManager.onSettings = { [weak self] in self?.settingsCoordinator.show() }
        menuBarManager.onReloadConfiguration = { [weak self] in self?.reloadConfiguration() }
        menuBarManager.onPreferencesChanged = { [weak self] preferences in
            self?.persistMenuPreferences(preferences)
        }
        menuBarManager.onQuit = { NSApp.terminate(nil) }
    }

    private func startControlLoop() {
        controlTask?.cancel()
        controlTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let telemetry = await controlSession.tick()
                let metrics = await sensorEngine.poll()
                telemetryStore.publish(telemetry)
                telemetryStore.publish(metrics: metrics)
                menuBarManager.update(telemetry: telemetry, metrics: metrics)
                let interval = max(0.1, settingsViewModel.configuration.controlTickInterval)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    private func reloadConfiguration() {
        Task { [weak self] in
            guard let self else { return }
            let result = await configStore.reload()
            await apply(result.configuration)
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
                try await configStore.resetToDefaults()
                await apply(.defaults)
            } catch {
                await eventLog.append(
                    timestamp: clock.now,
                    type: .configurationError,
                    detail: error.localizedDescription
                )
            }
        }
    }

    private func persistMenuPreferences(_ preferences: MenuBarPreferences) {
        var configuration = settingsViewModel.configuration
        configuration.menuBar = preferences
        settingsViewModel.configuration = configuration
        save(configuration)
    }

    private func save(_ configuration: Configuration) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try configuration.validate()
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

    private func apply(_ configuration: Configuration) async {
        settingsViewModel.configuration = configuration
        menuBarManager.apply(preferences: configuration.menuBar)
        try? loginItemManager.setEnabled(configuration.launchAtLogin)
        try? await controlSession.applyConfiguration(configuration)
    }
}
