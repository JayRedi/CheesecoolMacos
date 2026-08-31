import XCTest
import CheeseCoolCore
@testable import CheeseCool

final class MenuBarInvariantTests: XCTestCase {
    func testNoVisibleMetricsForcesMainIconVisible() {
        let visibility = MenuBarVisibilityPolicy.resolve(
            preferredMainIconVisible: false,
            visibleMetrics: []
        )
        XCTAssertTrue(visibility.mainIconVisible)
        XCTAssertTrue(visibility.visibleMetrics.isEmpty)
    }

    func testMetricsPermitPreferredMainIconState() {
        let hidden = MenuBarVisibilityPolicy.resolve(
            preferredMainIconVisible: false,
            visibleMetrics: [.fanRPM]
        )
        XCTAssertFalse(hidden.mainIconVisible)
        let shown = MenuBarVisibilityPolicy.resolve(
            preferredMainIconVisible: true,
            visibleMetrics: [.fanRPM, .socTemperature]
        )
        XCTAssertTrue(shown.mainIconVisible)
    }
}
