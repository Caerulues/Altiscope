import XCTest
@testable import AltiscopeCore

final class NavigationTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_000_000)
    func observation(_ time: Double, speed: Double? = 2, course: Double? = 90, coordinate: Coordinate = Coordinate(32,118)) -> GPSObservation {
        var gps = GPSObservation(); gps.coordinate = coordinate; gps.observedAt = start.addingTimeInterval(time)
        gps.speedMps = speed; gps.courseDeg = course; gps.horizontalAccuracyM = 5; gps.altitudeM = 100; gps.verticalAccuracyM = 3
        return gps
    }
    func testBearingUsesPreviousVelocityBeforeCompassAndHandlesNorthBoundary() {
        let compass = CompassObservation(degrees: 180, trueNorth: false, timestamp: start)
        let east = InertialNavigator.bearing(previous: VectorENU(east: 2, north: 0, up: 0), compass: compass, at: start)
        XCTAssertEqual(east.0, 90); XCTAssertEqual(east.1, "previous_velocity"); XCTAssertEqual(east.2, "true_north")
        let stopped = InertialNavigator.bearing(previous: VectorENU(east: 0, north: 0, up: 0), compass: compass, at: start)
        XCTAssertEqual(stopped.0, 180); XCTAssertEqual(stopped.2, "magnetic_north")
        XCTAssertNil(InertialNavigator.bearing(previous: nil, compass: compass, at: start.addingTimeInterval(6)).0)
        for angle in [359.9, 0.0, 0.1] {
            let bearing = InertialNavigator.bearing(previous: VectorENU(east: sin(angle * .pi / 180), north: cos(angle * .pi / 180), up: 0), compass: nil, at: start)
            XCTAssertEqual(bearing.0!, angle, accuracy: 0.0001)
        }
    }
    func testRotationTransposeAndENUAxisOrder() throws {
        let north = try XCTUnwrap(InertialNavigator.accelerationENU(device: VectorENU(east: 1, north: 0, up: 0), rotation: [1,0,0,0,1,0,0,0,1]))
        XCTAssertEqual(north, VectorENU(east: 0, north: 1, up: 0))
        let east = try XCTUnwrap(InertialNavigator.accelerationENU(device: VectorENU(east: 1, north: 0, up: 0), rotation: [0,-1,0,1,0,0,0,0,1]))
        XCTAssertEqual(east, VectorENU(east: 1, north: 0, up: 0))
        XCTAssertNil(InertialNavigator.accelerationENU(device: north, rotation: [1]))
    }
    func testStraightReplayAndBoundedLossOfSignal() throws {
        var navigator = InertialNavigator()
        XCTAssertTrue(navigator.correct(observation(0), monotonicTime: 0, timestamp: start, mode: .walking, compass: nil))
        let zero = VectorENU(east: 0, north: 0, up: 0)
        for index in 0...100 { navigator.predict(acceleration: zero, monotonicTime: Double(index)/20, timestamp: start.addingTimeInterval(Double(index)/20), compass: nil) }
        XCTAssertEqual(try XCTUnwrap(navigator.state.coordinate).distance(to: Coordinate(32,118)), 10, accuracy: 0.03)
        XCTAssertEqual(navigator.state.bearingDeg, 90)
        XCTAssertEqual(navigator.state.predictionAgeSeconds, 5)
        for index in 101...205 { navigator.predict(acceleration: zero, monotonicTime: Double(index)/20, timestamp: start.addingTimeInterval(Double(index)/20), compass: nil) }
        XCTAssertNil(navigator.state.coordinate); XCTAssertEqual(navigator.state.status, .invalid); XCTAssertEqual(navigator.segmentId, 1)
    }
    func testStationaryReplayDoesNotMoveWithoutAcceleration() throws {
        var navigator = InertialNavigator()
        XCTAssertTrue(navigator.correct(observation(0, speed: 0, course: nil), monotonicTime: 0, timestamp: start, mode: .walking, compass: nil))
        for index in 0...100 { navigator.predict(acceleration: VectorENU(east: 0, north: 0, up: 0), monotonicTime: Double(index)/20, timestamp: start.addingTimeInterval(Double(index)/20), compass: nil) }
        XCTAssertEqual(navigator.state.coordinate, Coordinate(32,118)); XCTAssertEqual(navigator.state.speedMps, 0)
    }
    func testFiveSecondChecksRejectReusedFixesAndTeleport() {
        var navigator = InertialNavigator()
        let first = observation(0)
        XCTAssertTrue(navigator.correct(first, monotonicTime: 0, timestamp: start, mode: .walking, compass: nil))
        XCTAssertFalse(navigator.correct(observation(1), monotonicTime: 1, timestamp: start.addingTimeInterval(1), mode: .walking, compass: nil))
        XCTAssertFalse(navigator.correct(first, monotonicTime: 5, timestamp: start.addingTimeInterval(5), mode: .walking, compass: nil))
        XCTAssertFalse(navigator.correct(observation(10, coordinate: Coordinate(40,120)), monotonicTime: 10, timestamp: start.addingTimeInterval(10), mode: .walking, compass: nil))
        XCTAssertEqual(navigator.state.lastCorrectionAt, start)
    }
    func testPauseMissingAttitudeAndMotionGapNeverBridgePrediction() {
        var navigator = InertialNavigator()
        XCTAssertTrue(navigator.correct(observation(0), monotonicTime: 0, timestamp: start, mode: .walking, compass: nil))
        navigator.predict(acceleration: VectorENU(east: 0, north: 0, up: 0), monotonicTime: 0, timestamp: start, compass: nil)
        navigator.predict(acceleration: VectorENU(east: 0, north: 0, up: 0), monotonicTime: 2, timestamp: start.addingTimeInterval(2), compass: nil)
        XCTAssertNil(navigator.state.coordinate); XCTAssertEqual(navigator.segmentId, 1)
        navigator.reset(segmentId: 9); XCTAssertEqual(navigator.segmentId, 9); XCTAssertNil(navigator.state.velocityENU)
        navigator.predict(acceleration: nil, monotonicTime: 3, timestamp: start, compass: nil)
        XCTAssertEqual(navigator.state.status, .invalid)
    }
    func testScalarSpeedCannotInventVelocityAndPartialGPSFieldsRemainIndependent() {
        var navigator = InertialNavigator()
        let compass = CompassObservation(degrees: 90, trueNorth: true, timestamp: start)
        XCTAssertFalse(navigator.correct(observation(0, speed: 4, course: nil), monotonicTime: 0, timestamp: start, mode: .walking, compass: compass))
        XCTAssertNil(navigator.state.coordinate)
        var gps = observation(0); gps.speedMps = nil
        XCTAssertNotNil(gps.fresh(at: start).coordinate); XCTAssertNil(gps.fresh(at: start).speedMps)
        XCTAssertNil(gps.fresh(at: start.addingTimeInterval(3)).coordinate)
    }
    func testSystemObservationValidityDoesNotDiscardIndependentFields() {
        let partial = GPSObservation(measuredCoordinate: Coordinate(32,118), observedAt: start, horizontalAccuracyM: -1,
                                     altitudeM: -12, verticalAccuracyM: 3, speedMps: 2, courseDeg: -1)
        XCTAssertNil(partial.coordinate); XCTAssertNil(partial.horizontalAccuracyM); XCTAssertNil(partial.courseDeg)
        XCTAssertEqual(partial.altitudeM, -12); XCTAssertEqual(partial.speedMps, 2)
        XCTAssertEqual(partial.observedAt, start)
        let horizontal = GPSObservation(measuredCoordinate: Coordinate(0,0), observedAt: start, horizontalAccuracyM: 5,
                                        altitudeM: 100, verticalAccuracyM: -1, speedMps: .nan, courseDeg: 360)
        XCTAssertEqual(horizontal.coordinate, Coordinate(0,0)); XCTAssertNil(horizontal.altitudeM)
        XCTAssertNil(horizontal.speedMps); XCTAssertNil(horizontal.courseDeg)
    }
    func testWallClockJumpDoesNotChangeMonotonicIntegration() throws {
        var navigator = InertialNavigator()
        XCTAssertTrue(navigator.correct(observation(0), monotonicTime: 0, timestamp: start, mode: .walking, compass: nil))
        for index in 0...20 { navigator.predict(acceleration: VectorENU(east: 0, north: 0, up: 0), monotonicTime: Double(index)/20, timestamp: start.addingTimeInterval(3600 + Double(index)/20), compass: nil) }
        XCTAssertEqual(try XCTUnwrap(navigator.state.coordinate).distance(to: Coordinate(32,118)), 2, accuracy: 0.01)
    }
}
