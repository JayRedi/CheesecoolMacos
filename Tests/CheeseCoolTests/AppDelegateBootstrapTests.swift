import AppKit
import XCTest
@testable import CheeseCool

@MainActor
final class AppDelegateBootstrapTests: XCTestCase {
    func testProgrammaticBootstrapInstallsApplicationDelegate() {
        XCTAssertTrue(NSApplication.shared.delegate is AppDelegate)
    }
}
