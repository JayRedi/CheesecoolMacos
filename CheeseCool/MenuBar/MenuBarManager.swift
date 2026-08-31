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
    private var latestTelemetry: TelemetrySnapshot?
    private var latestMetrics: MetricsSnapshot?

    public var onSettings: (() -> Void)?
    public var onQuit: (() -> Void)?
    public var onModeSelected: ((OperatingMode) -> Void)?
    public var onMetricVisibilityChanged: ((MetricIdentifier, Bool) -> Void)?

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
        latestTelemetry = telemetry
        latestMetrics = metrics
        let latestUnsupported = MetricAvailabilityPolicy.unsupportedMetrics(in: metrics)
        if latestUnsupported != unsupportedMetrics {
            unsupportedMetrics = latestUnsupported
            rebuildForCurrentSupport()
        }
        metricControllers[.fanRPM]?.update(title: MenuMetricFormatter.title(for: .fanRPM, value: telemetry.rpm.map(Double.init)))
        metricControllers[.fanDuty]?.update(title: MenuMetricFormatter.title(for: .fanDuty, value: telemetry.deviceActualDuty.map(Double.init)))
        metricControllers[.socTemperature]?.update(title: MenuMetricFormatter.title(for: .socTemperature, value: metrics?.socTemperatureCelsius))
        metricControllers[.cpuLoad]?.update(title: MenuMetricFormatter.title(for: .cpuLoad, value: metrics?.cpuLoadPercent))
    }

    private func rebuildMetricItems(visibility: MenuBarVisibility) {
        for controller in metricControllers.values { controller.hide() }
        metricControllers.removeAll()
        for metric in preferences.metricOrder where visibility.visibleMetrics.contains(metric) {
            let controller = MetricStatusItemController(metric: metric, statusBar: statusBar)
            controller.show(title: placeholder(for: metric), menu: makeMenu(for: metric))
            metricControllers[metric] = controller
        }
    }

    private func setMainIconVisible(_ visible: Bool) {
        if visible, mainStatusItem == nil {
            let item = statusBar.statusItem(withLength: NSStatusItem.squareLength)
            if let image = NSImage(systemSymbolName: "fan.fill", accessibilityDescription: "CheeseCool") {
                let configuration = NSImage.SymbolConfiguration(pointSize: Self.mainIconPointSize, weight: .medium)
                let configuredImage = image.withSymbolConfiguration(configuration) ?? image
                configuredImage.isTemplate = true
                item.button?.image = configuredImage
                item.button?.imagePosition = .imageOnly
                item.button?.imageScaling = .scaleProportionallyDown
                item.button?.setAccessibilityLabel("CheeseCool 菜单")
            } else {
                item.button?.title = "C"
            }
            item.button?.toolTip = "CheeseCool"
            item.menu = makeMenu()
            item.isVisible = true
            mainStatusItem = item
        } else if !visible, let mainStatusItem {
            statusBar.removeStatusItem(mainStatusItem)
            self.mainStatusItem = nil
        } else if visible {
            mainStatusItem?.menu = makeMenu()
        }
    }

    func makeMenu(for metric: MetricIdentifier? = nil) -> NSMenu {
        let menu = NSMenu(title: "CheeseCool")
        if let metric {
            menu.addItem(disabledItem(title: metric.displayName))
            menu.addItem(actionItem(title: "隐藏\(metric.displayName)", action: #selector(hideMetric(_:)), representedObject: metric.rawValue))
            menu.addItem(.separator())
        } else {
            menu.addItem(disabledItem(title: statusSummary))
            for mode in OperatingMode.allCases {
                let item = actionItem(title: mode.productName, action: #selector(selectMode(_:)), representedObject: mode.rawValue)
                item.state = (latestTelemetry?.operatingMode ?? .auto) == mode ? .on : .off
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }
        menu.addItem(actionItem(title: "设置…", action: #selector(openSettings)))
        menu.addItem(.separator())
        menu.addItem(actionItem(title: "退出 CheeseCool", action: #selector(quit)))
        return menu
    }

    private var statusSummary: String {
        guard let telemetry = latestTelemetry else { return "当前状态：正在准备" }
        if telemetry.controlState.isCritical { return "当前状态：电源故障" }
        let temperature = MenuMetricFormatter.title(for: .socTemperature, value: latestMetrics?.socTemperatureCelsius)
        return "当前状态：\(telemetry.controlState.displayName) · \(temperature)"
    }

    private func actionItem(title: String, action: Selector, representedObject: Any? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = representedObject
        return item
    }

    private func disabledItem(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func placeholder(for metric: MetricIdentifier) -> String {
        MenuMetricFormatter.title(for: metric, value: nil)
    }

    @objc private func openSettings() { onSettings?() }
    @objc private func quit() { onQuit?() }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String, let mode = OperatingMode(rawValue: rawValue) else { return }
        onModeSelected?(mode)
    }

    @objc private func hideMetric(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String, let metric = MetricIdentifier(rawValue: rawValue) else { return }
        onMetricVisibilityChanged?(metric, false)
    }
}
