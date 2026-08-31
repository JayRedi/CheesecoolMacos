import AppKit
import XCTest
import CheeseCoolCore
@testable import CheeseCool

@MainActor
final class UserFacingTextTests: XCTestCase {
    func testOperatingModesUseChineseDisplayNames() {
        XCTAssertEqual(OperatingMode.auto.displayName, "自动")
        XCTAssertEqual(OperatingMode.manual.displayName, "手动")
        XCTAssertEqual(OperatingMode.max.displayName, "全速")
    }

    func testMetricsUseChineseDisplayNames() {
        XCTAssertEqual(MetricIdentifier.fanRPM.displayName, "风扇转速")
        XCTAssertEqual(MetricIdentifier.fanDuty.displayName, "风扇占空比")
        XCTAssertEqual(MetricIdentifier.socTemperature.displayName, "芯片温度")
        XCTAssertEqual(MetricIdentifier.cpuLoad.displayName, "处理器负载")
        XCTAssertEqual(MetricIdentifier.socPower.displayName, "芯片功耗")
        XCTAssertEqual(MetricIdentifier.gpuLoad.displayName, "图形处理器负载")
    }

    func testMainMenuShowsStatusModesSettingsAndQuit() {
        let titles = MenuBarManager().makeMenu().items.map(\.title)

        XCTAssertEqual(titles, [
            "当前状态：正在准备", "自动（AUTO）", "手动（MANUAL）", "全速（MAX）",
            "", "设置…", "", "退出 CheeseCool"
        ])
    }

    func testMainIconUsesNativeMenuBarScale() {
        XCTAssertEqual(MenuBarManager.mainIconPointSize, 17)
    }
}
