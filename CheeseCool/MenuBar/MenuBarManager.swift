import AppKit
import CheeseCoolCore
import OSLog

@MainActor
public final class MenuBarManager: NSObject {
    static let mainIconPointSize: CGFloat = 17
    private let logger = Logger(subsystem: "org.cheesecool.CheeseCool", category: "MenuBar")
    private let statusBar: NSStatusBar
    private var mainStatusItem: NSStatusItem?
    private var metricControllers: [MetricIdentifier: MetricStatusItemController] = [:]
    private var preferences: MenuBarPreferences = .init()
    private var unsupportedMetrics: Set<MetricIdentifier> = []

    public var onSettings: (() -> Void)?
    public var onQuit: (() -> Void)?

    public override init() {
        self.statusBar = .system
        super.init()
    }

    public init(statusBar: NSStatusBar) {
        self.statusBar = statusBar
        super.init()
    }

    public func apply(preferences: MenuBarPreferences) {
        self.preferences = preferences
        rebuildForCurrentSupport()
    }

    private func rebuildForCurrentSupport() {
        let effectiveMetrics = Set(preferences.visibleMetrics).subtracting(unsupportedMetrics)
        let visibility = MenuBarVisibilityPolicy.resolve(
            preferredMainIconVisible: preferences.mainIconPreferredVisible,
            visibleMetrics: effectiveMetrics
        )
        rebuildMetricItems(visibility: visibility)
        setMainIconVisible(visibility.mainIconVisible)
        logger.notice(
            "Applied menu bar preferences: mainIconVisible=\(visibility.mainIconVisible, privacy: .public), visibleMetricCount=\(visibility.visibleMetrics.count, privacy: .public)"
        )
    }

    public func update(telemetry: TelemetrySnapshot, metrics: MetricsSnapshot?) {
        let latestUnsupported = MetricAvailabilityPolicy.unsupportedMetrics(in: metrics)
        if latestUnsupported != unsupportedMetrics {
            unsupportedMetrics = latestUnsupported
            rebuildForCurrentSupport()
        }
        metricControllers[.fanRPM]?.update(
            title: MenuMetricFormatter.title(for: .fanRPM, value: telemetry.rpm.map(Double.init))
        )
        metricControllers[.fanDuty]?.update(
            title: MenuMetricFormatter.title(for: .fanDuty, value: telemetry.deviceActualDuty.map(Double.init))
        )
        metricControllers[.socTemperature]?.update(
            title: MenuMetricFormatter.title(for: .socTemperature, value: metrics?.socTemperatureCelsius)
        )
        metricControllers[.cpuLoad]?.update(
            title: MenuMetricFormatter.title(for: .cpuLoad, value: metrics?.cpuLoadPercent)
        )
        metricControllers[.socPower]?.update(
            title: MenuMetricFormatter.title(for: .socPower, value: metrics?.socPowerWatts)
        )
        metricControllers[.gpuLoad]?.update(
            title: MenuMetricFormatter.title(for: .gpuLoad, value: metrics?.gpuLoadPercent)
        )
    }

    private func rebuildMetricItems(visibility: MenuBarVisibility) {
        for controller in metricControllers.values { controller.hide() }
        metricControllers.removeAll()
        for metric in preferences.metricOrder where visibility.visibleMetrics.contains(metric) {
            let controller = MetricStatusItemController(metric: metric, statusBar: statusBar)
            controller.show(title: placeholder(for: metric), menu: makeMenu())
            metricControllers[metric] = controller
        }
    }

    private func setMainIconVisible(_ visible: Bool) {
        if visible, mainStatusItem == nil {
            let item = statusBar.statusItem(withLength: NSStatusItem.squareLength)
            if let image = NSImage(systemSymbolName: "fan.fill", accessibilityDescription: "CheeseCool") {
                let configuration = NSImage.SymbolConfiguration(
                    pointSize: Self.mainIconPointSize,
                    weight: .medium
                )
                let configuredImage = image.withSymbolConfiguration(configuration) ?? image
                configuredImage.isTemplate = true
                item.button?.image = configuredImage
                item.button?.imagePosition = .imageOnly
                item.button?.imageScaling = .scaleProportionallyDown
            } else {
                item.button?.title = "C"
            }
            item.button?.toolTip = "CheeseCool"
            item.menu = makeMenu()
            item.isVisible = true
            mainStatusItem = item
            logger.notice(
                "Created main status item: buttonAvailable=\(item.button != nil, privacy: .public), visible=\(item.isVisible, privacy: .public)"
            )
        } else if !visible, let mainStatusItem {
            statusBar.removeStatusItem(mainStatusItem)
            self.mainStatusItem = nil
        } else if visible {
            mainStatusItem?.menu = makeMenu()
        }
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "CheeseCool")
        menu.addItem(actionItem(title: "设置…", action: #selector(openSettings)))
        menu.addItem(.separator())
        menu.addItem(actionItem(title: "退出 CheeseCool", action: #selector(quit)))
        return menu
    }

    private func actionItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func placeholder(for metric: MetricIdentifier) -> String {
        MenuMetricFormatter.title(for: metric, value: nil)
    }

    @objc private func openSettings() { onSettings?() }
    @objc private func quit() { onQuit?() }
}
