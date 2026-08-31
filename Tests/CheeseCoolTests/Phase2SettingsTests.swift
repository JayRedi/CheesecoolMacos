import XCTest
import CheeseCoolCore
@testable import CheeseCool

@MainActor
final class Phase2SettingsTests: XCTestCase {
    func testSettingsChangeTriggersImmediateAutoSaveCallback() {
        let model = SettingsViewModel(configuration: .defaults)
        let called = expectation(description: "configuration changed")
        var received: Configuration?
        model.onConfigurationChanged = {
            received = $0
            called.fulfill()
        }
        model.configuration.manualDuty = 61
        wait(for: [called], timeout: 0.1)
        XCTAssertEqual(received?.manualDuty, 61)
    }

    func testReplacingLoadedConfigurationDoesNotTriggerAutoSaveLoop() {
        let model = SettingsViewModel(configuration: .defaults)
        var callCount = 0
        model.onConfigurationChanged = { _ in callCount += 1 }
        var loaded = Configuration.defaults
        loaded.manualDuty = 72
        model.replaceConfiguration(loaded)
        XCTAssertEqual(model.configuration.manualDuty, 72)
        XCTAssertEqual(callCount, 0)
    }

    func testSettingsSurfaceHasNoFileOrReloadAffordances() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repository.appendingPathComponent("CheeseCool/Settings/SettingsView.swift"),
            encoding: .utf8
        )
        for forbidden in ["重新载入配置", "重载配置", "打开配置文件夹", "配置文件路径", "Button(\"保存\")"] {
            XCTAssertFalse(source.contains(forbidden), "Unexpected product affordance: \(forbidden)")
        }
    }

    func testMenuMetricFormattingAndUnavailablePlaceholders() {
        XCTAssertEqual(MenuMetricFormatter.title(for: .socTemperature, value: 42.4), "42°C")
        XCTAssertEqual(MenuMetricFormatter.title(for: .cpuLoad, value: 18.2), "18%")
        XCTAssertEqual(MenuMetricFormatter.title(for: .socPower, value: 6.75), "6.8 W")
        XCTAssertEqual(MenuMetricFormatter.title(for: .gpuLoad, value: 23), "23%")
        XCTAssertEqual(MenuMetricFormatter.title(for: .socTemperature, value: nil), "--°C")
        XCTAssertEqual(MenuMetricFormatter.title(for: .cpuLoad, value: nil), "--%")
        XCTAssertEqual(MenuMetricFormatter.title(for: .socPower, value: nil), "-- W")
    }
}
