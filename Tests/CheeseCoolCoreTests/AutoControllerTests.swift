import XCTest
@testable import CheeseCoolCore

final class AutoControllerTests: XCTestCase {
    private func sample(
        _ temperature: Double?,
        timestamp: TimeInterval,
        state: TemperatureState? = nil,
        valid: Bool = true
    ) -> TemperatureSample {
        TemperatureSample(
            timestamp: timestamp,
            controlTemperatureCelsius: temperature,
            state: state ?? temperature.map(TemperatureClassifier.classify) ?? .unknown,
            valid: valid,
            sourceStatus: valid ? .ok : .unavailable,
            sensorCount: valid ? 1 : 0
        )
    }

    func testFrozenCurvePointsAndInterpolation() {
        XCTAssertEqual(AutoController.interpolate(temperatureCelsius: 30), 0)
        XCTAssertEqual(AutoController.interpolate(temperatureCelsius: 40), 0)
        XCTAssertEqual(AutoController.interpolate(temperatureCelsius: 45), 12.5)
        XCTAssertEqual(AutoController.interpolate(temperatureCelsius: 50), 25)
        XCTAssertEqual(AutoController.interpolate(temperatureCelsius: 55), 32.5)
        XCTAssertEqual(AutoController.interpolate(temperatureCelsius: 60), 40)
        XCTAssertEqual(AutoController.interpolate(temperatureCelsius: 70), 60)
        XCTAssertEqual(AutoController.interpolate(temperatureCelsius: 80), 80)
        XCTAssertEqual(AutoController.interpolate(temperatureCelsius: 90), 100)
        XCTAssertEqual(AutoController.interpolate(temperatureCelsius: 100), 100)
    }

    func testDeadbandHoldsPreviousDuty() {
        var controller = AutoController()
        let first = controller.update(sample: sample(50, timestamp: 0), now: 0)
        let second = controller.update(sample: sample(50.5, timestamp: 1), now: 1)
        XCTAssertEqual(first.requestedDuty, 25)
        XCTAssertEqual(second.requestedDuty, 25)
        XCTAssertEqual(second.reason, .dutyDeadband)
    }

    func testRampUpAndDown() {
        var up = AutoController()
        _ = up.update(sample: sample(40, timestamp: 0), now: 0)
        let raised = up.update(sample: sample(80, timestamp: 1), now: 1)
        XCTAssertEqual(raised.requestedDuty, 20)
        XCTAssertEqual(raised.reason, .rampUpLimit)

        var down = AutoController()
        _ = down.update(sample: sample(80, timestamp: 0), now: 0)
        let lowered = down.update(sample: sample(40, timestamp: 1), now: 1)
        XCTAssertEqual(lowered.requestedDuty, 72)
        XCTAssertEqual(lowered.reason, .rampDownLimit)
    }

    func testCriticalImmediatelyOverridesRamp() {
        var controller = AutoController()
        _ = controller.update(sample: sample(40, timestamp: 0), now: 0)
        let critical = controller.update(
            sample: sample(85, timestamp: 0.1, state: .critical),
            now: 0.1
        )
        XCTAssertEqual(critical.requestedDuty, 100)
        XCTAssertEqual(critical.reason, .criticalOverride)
    }

    func testTemperatureGraceBoundaryAndExpiry() {
        var controller = AutoController()
        _ = controller.update(sample: sample(60, timestamp: 0), now: 0)
        let boundary = controller.update(sample: sample(nil, timestamp: 3, valid: false), now: 3)
        XCTAssertTrue(boundary.valid)
        XCTAssertEqual(boundary.reason, .temperatureGraceHold)
        let expired = controller.update(sample: sample(nil, timestamp: 3.001, valid: false), now: 3.001)
        XCTAssertFalse(expired.valid)
        XCTAssertNil(expired.requestedDuty)
        XCTAssertEqual(expired.reason, .temperatureUnavailable)
    }

    func testInvalidStaleAndNaNNeverControlDuty() {
        var noHistory = AutoController()
        XCTAssertFalse(noHistory.update(sample: sample(nil, timestamp: 0, valid: false), now: 0).valid)
        var stale = AutoController()
        XCTAssertFalse(stale.update(sample: sample(50, timestamp: 0), now: 6).valid)
        var nan = AutoController()
        XCTAssertFalse(nan.update(sample: sample(.nan, timestamp: 0, state: .normal), now: 0).valid)
    }

    func testZeroElapsedCannotJump() {
        var controller = AutoController()
        _ = controller.update(sample: sample(50, timestamp: 10), now: 10)
        let decision = controller.update(sample: sample(80, timestamp: 10), now: 10)
        XCTAssertEqual(decision.requestedDuty, 25)
    }
}
