import Foundation
import XCTest
import CheeseCoolCore
@testable import CheeseCool

@MainActor
final class Phase3ProductPolishTests: XCTestCase {
    func testMetricMenuIsConciseAndContainsNoConfigurationActions() {
        let titles = MenuBarManager().makeMenu(for: .socTemperature).items.map(\.title)
        XCTAssertEqual(titles, ["芯片温度", "隐藏芯片温度", "", "设置…", "", "退出 CheeseCool"])
        XCTAssertFalse(titles.contains { $0.contains("配置") || $0.contains("重载") })
    }

    func testStatusLabelsAreChineseAndPowerFaultIsCritical() {
        XCTAssertEqual(ConnectionState.connected.displayName, "已连接")
        XCTAssertEqual(ControlState.temperatureUnavailable.displayName, "温度暂不可用，已进入安全保护")
        XCTAssertEqual(ControlState.powerFault.displayName, "电源故障")
        XCTAssertTrue(ControlState.powerFault.isCritical)
        XCTAssertEqual(SensorSourceStatus.unsupported.displayName, "当前系统不支持")
    }

    func testManualZeroIsClampedAndKeepsMinimumSpeedMeaning() {
        let model = SettingsViewModel(configuration: .defaults)
        model.setManualDuty(-20)
        XCTAssertEqual(model.configuration.manualDuty, 0)
        model.setManualDuty(180)
        XCTAssertEqual(model.configuration.manualDuty, 100)
    }

    func testCurveEditorKeepsCurveStrictlyOrderedAndDutyInRange() throws {
        let model = SettingsViewModel(configuration: .defaults)
        model.setAutoCurvePoint(at: 2, temperature: 1_000, duty: 500)
        XCTAssertEqual(model.configuration.autoCurve[2].temperatureCelsius, 69)
        XCTAssertEqual(model.configuration.autoCurve[2].duty, 100)
        XCTAssertNoThrow(try model.configuration.validate())
    }

    func testMetricOrderCanMoveWithoutChangingMetricSet() {
        let model = SettingsViewModel(configuration: .defaults)
        model.moveMetric(.cpuLoad, by: -1)
        XCTAssertEqual(Set(model.configuration.menuBar.metricOrder), Set(MetricIdentifier.allCases))
        XCTAssertEqual(model.configuration.menuBar.metricOrder.count, MetricIdentifier.allCases.count)
    }

    func testResetIsAnExplicitCallback() {
        let model = SettingsViewModel(configuration: .defaults)
        var resetCount = 0
        model.onReset = { resetCount += 1 }
        model.reset()
        XCTAssertEqual(resetCount, 1)
    }

    func testLifecycleRouterRoutesSleepWakeOnlyWhileStarted() async {
        let center = NotificationCenter()
        let sleep = Notification.Name("phase3.sleep")
        let wake = Notification.Name("phase3.wake")
        var events: [String] = []
        let router = LifecycleNotificationRouter(
            notificationCenter: center,
            sleepNotification: sleep,
            wakeNotification: wake,
            onSleep: { events.append("sleep") },
            onWake: { events.append("wake") }
        )
        router.start()
        center.post(name: sleep, object: nil)
        center.post(name: wake, object: nil)
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(events, ["sleep", "wake"])
        router.stop()
        center.post(name: sleep, object: nil)
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(events, ["sleep", "wake"])
    }

    func testSettingsCoordinatorCreatesOnlyOneWindow() {
        let coordinator = SettingsCoordinator(model: SettingsViewModel(configuration: .defaults))
        XCTAssertEqual(coordinator.windowInstanceCount, 0)
        coordinator.show()
        coordinator.show()
        XCTAssertEqual(coordinator.windowInstanceCount, 1)
    }

    func testAppIconCatalogHasAllMacRepresentationsAndNoPlaceholder() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = repository.appendingPathComponent("CheeseCool/Resources/Assets.xcassets/AppIcon.appiconset")
        let contents = try String(contentsOf: catalog.appendingPathComponent("Contents.json"), encoding: .utf8)
        for filename in [
            "icon_16x16.png", "icon_16x16@2x.png", "icon_32x32.png", "icon_32x32@2x.png",
            "icon_128x128.png", "icon_128x128@2x.png", "icon_256x256.png", "icon_256x256@2x.png",
            "icon_512x512.png", "icon_512x512@2x.png"
        ] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: catalog.appendingPathComponent(filename).path))
            XCTAssertTrue(contents.contains(filename))
        }
        XCTAssertFalse(contents.localizedCaseInsensitiveContains("hammer"))
    }
}
