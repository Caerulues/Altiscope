import XCTest
@testable import AltiscopeCore

final class CoordinateTransformTests: XCTestCase {
    func testUpstreamExamplesAndLongitudeLatitudeOrder() {
        let origin = Coordinate(39.915, 116.404)
        let result = CoordTransform.wgs84ToGCJ02(origin)
        XCTAssertEqual(result.latitude, 39.91640428150164, accuracy: 1e-11)
        XCTAssertEqual(result.longitude, 116.41024449916938, accuracy: 1e-11)
        let inverse = CoordTransform.gcj02ToWGS84(origin)
        XCTAssertEqual(inverse.latitude, 39.91359571849836, accuracy: 1e-11)
        XCTAssertEqual(inverse.longitude, 116.39775550083061, accuracy: 1e-11)
        XCTAssertLessThan(CoordTransform.gcj02ToWGS84(result).distance(to: origin), 2)
    }
    func testVerifiedRegionGateExcludesHongKongMacauTaiwanAndForeignPoints() {
        for (coordinate, code) in [(Coordinate(22.3193,114.1694),"HK"), (Coordinate(22.1987,113.5439),"MO"),
                                   (Coordinate(25.033,121.5654),"TW"), (Coordinate(21.0285,105.8542),"VN"),
                                   (Coordinate(35.6762,139.6503),"JP")] {
            let input = DisplayCoordinate(coordinate, reference: .wgs84)
            let result = input.adapted(to: .gcj02, region: DisplayRegion(verifiedCountryCode: code, boundaryIsUncertain: false))
            XCTAssertEqual(result.value, coordinate); XCTAssertEqual(result.reference, .wgs84)
        }
    }
    func testUncertainBoundaryIsNotGuessedAndTaggedValuesAreNotDoubleConverted() {
        let point = Coordinate(22.53,114.1)
        let input = DisplayCoordinate(point, reference: .wgs84)
        XCTAssertEqual(input.adapted(to: .gcj02, region: DisplayRegion(verifiedCountryCode: "CN", boundaryIsUncertain: true)).value, point)
        XCTAssertEqual(input.adapted(to: .gcj02, region: .unverifiedBoundary).value, point)
        let converted = input.adapted(to: .gcj02, region: .confirmedMainland)
        XCTAssertNotEqual(converted.value, point)
        XCTAssertEqual(converted.adapted(to: .gcj02, region: .confirmedMainland).value, converted.value)
        XCTAssertEqual(DisplayCoordinate.mapKitInput(point), point)
    }
    func testUpstreamRectangleEdgesDoNotClaimGeographicBoundary() {
        for point in [Coordinate(3.86,100), Coordinate(53.55,100), Coordinate(30,73.66), Coordinate(30,135.05), Coordinate(0,0)] {
            XCTAssertTrue(CoordTransform.outsideUpstreamRectangle(point)); XCTAssertEqual(CoordTransform.wgs84ToGCJ02(point), point)
        }
        // Hanoi passes the upstream rectangle but the verified-region gate above excludes it.
        XCTAssertFalse(CoordTransform.outsideUpstreamRectangle(Coordinate(21.0285,105.8542)))
    }
}
