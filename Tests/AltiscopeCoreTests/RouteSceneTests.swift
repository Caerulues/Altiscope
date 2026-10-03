import XCTest
@testable import AltiscopeCore

final class RouteSceneTests: XCTestCase {
    private func point(_ longitude: Double, _ altitude: Double?, segment: Int = 0) -> TrackPoint {
        TrackPoint(timestamp: nil, coordinate: Coordinate(32, longitude), altitude: altitude, segment: segment)
    }
    func testMSLZeroClimbDescentAndNegativeHeightRemainAbsolute() {
        let points = [point(118,100),point(118.001,1000),point(118.002,1000),point(118.003,0),point(118.004,-80)]
        let scene = RouteScene(points: points, altitudeReference: "MSL")
        XCTAssertEqual(scene.vertices.map(\.position.z), [100,1000,1000,0,-80])
        XCTAssertEqual(scene.maximumHeight, 1000); XCTAssertEqual(scene.minimumHeight, -80)
        XCTAssertEqual(scene.edges.count, 4)
        XCTAssertEqual(scene.vertices.first?.position.x, 0)
        XCTAssertEqual(points.map(\.altitude), [100,1000,1000,0,-80])
    }
    func testMissingHeightAndPausesBreakBothMainLineAndCurtain() {
        let scene = RouteScene(points: [point(118,0),point(118.001,100),point(118.002,nil),
            point(118.003,200),point(118.004,300,segment:1),point(118.005,400,segment:1)], altitudeReference:"MSL")
        XCTAssertEqual(scene.vertices.count,5); XCTAssertEqual(scene.edges.count,2)
        XCTAssertTrue(scene.edges.allSatisfy { $0.a.point.segment == $0.b.point.segment })
        XCTAssertFalse(scene.edges.contains { $0.a.position.z == 100 && $0.b.position.z == 200 })
        XCTAssertTrue(RouteScene(points:[point(118,100)],altitudeReference:"unknown").vertices.isEmpty)
    }
    func testZeroCrossingSplitsCurtainWithoutChangingRecordedPoints() {
        let scene = RouteScene(points:[point(118,-100),point(118.002,100)],altitudeReference:"MSL")
        XCTAssertEqual(scene.vertices.count,2); XCTAssertEqual(scene.edges.count,2)
        XCTAssertEqual(scene.edges[0].b.position.z,0)
        XCTAssertEqual(scene.edges[0].b.position,scene.edges[1].a.position)
        XCTAssertEqual(scene.edges[0].b.position.x,scene.vertices[1].position.x/2,accuracy:0.001)
    }
    func testDatelineUsesShortProjectionAndPreservesEstimatedSource() {
        var a = TrackPoint(timestamp:nil,coordinate:Coordinate(10,179.999),altitude:100)
        let b = TrackPoint(timestamp:nil,coordinate:Coordinate(10,-179.999),altitude:200)
        a.estimated = true
        let scene = RouteScene(points:[a,b],altitudeReference:"MSL")
        XCTAssertLessThan(abs(scene.vertices[1].position.x),230)
        XCTAssertTrue(scene.edges[0].estimated)
    }
    func testCalibratedXYZMatchesKnownCameraAcrossRotationPitchZoomAndViewport() throws {
        let ground = [SIMD2<Double>(-300,-300),SIMD2(300,-300),SIMD2(300,300),SIMD2(-300,300)]
        for pitch in [0.0,10,35,55,70] {
            for heading in [0.0,35,90,185,359] {
                for distance in [1800.0,25000] {
                    for viewport in [SIMD2<Double>(390,500),SIMD2(1100,780)] {
                        let focal = viewport.y*1.3
                        let p=pitch * .pi/180, h=heading * .pi/180
                        func screen(_ value: SIMD3<Double>) -> SIMD2<Double> {
                            let x=value.x*cos(h)-value.y*sin(h), y=value.x*sin(h)+value.y*cos(h)
                            let depth=distance-y*sin(p)-value.z*cos(p)
                            return SIMD2(focal*x/depth+viewport.x/2,focal*(y*cos(p)-value.z*sin(p))/depth+viewport.y/2)
                        }
                        let projection = try XCTUnwrap(RouteProjection.calibrate(ground:ground,
                            screen:ground.map { screen(SIMD3($0.x,$0.y,0)) },viewport:viewport,cameraAltitude:distance*cos(p)))
                        for value in [SIMD3<Double>(-400,-200,0),SIMD3(80,130,600),SIMD3(10,0,-150)] {
                            let actual = try XCTUnwrap(projection.screen(value)), expected=screen(value)
                            XCTAssertEqual(actual.x,expected.x,accuracy:0.001)
                            XCTAssertEqual(actual.y,expected.y,accuracy:0.001)
                        }
                    }
                }
            }
        }
    }
    func testInvalidProjectionAndVerticesBehindCameraDoNotMakeVisibleGeometry() throws {
        XCTAssertNil(RouteProjection.calibrate(ground:Array(repeating:.zero,count:4),screen:Array(repeating:.zero,count:4),viewport:SIMD2(400,400),cameraAltitude:100))
        let ground = [SIMD2<Double>(-100,-100),SIMD2(100,-100),SIMD2(100,100),SIMD2(-100,100)]
        let projection = try XCTUnwrap(RouteProjection.calibrate(ground:ground,screen:ground.map { $0+SIMD2(200,200) },viewport:SIMD2(400,400),cameraAltitude:1000))
        XCTAssertNil(projection.screen(SIMD3(0,0,1100)))
        XCTAssertEqual(projection.screen(SIMD3(0,0,0)),SIMD2(200,200))
    }
    func testLongSpiralDisplayRetainsAltitudeExtremaAndDoesNotAlterSource() {
        let points = (0..<20000).map { i -> TrackPoint in
            let angle=Double(i)*0.009
            return TrackPoint(timestamp:nil,coordinate:Coordinate(32+sin(angle)*0.01,118+cos(angle)*0.01),
                altitude:i == 10003 ? 12000 : Double(i%1000),segment:i<10000 ? 0:1)
        }
        let sampled = RouteDisplay.sampled(points,limit:1800)
        let scene = RouteScene(points:sampled,altitudeReference:"MSL")
        XCTAssertEqual(scene.maximumHeight,12000)
        XCTAssertEqual(scene.vertices.first?.point.id,points.first?.id)
        XCTAssertEqual(scene.vertices.last?.point.id,points.last?.id)
        XCTAssertTrue(scene.edges.allSatisfy { $0.a.point.segment == $0.b.point.segment })
        XCTAssertEqual(points.count,20000)
        let a = DisplayUnits.metric.altitude(12000), b = DisplayUnits.aviation.altitude(12000)
        XCTAssertNotEqual(a,b); XCTAssertEqual(scene.maximumHeight,12000)
    }
    func testSamplingKeepsSharpPlanViewTurnAndUnchangedRawCount() {
        var points = (0..<100).map { point(118+Double($0)*0.001,100) }
        points[25].coordinate.latitude += 0.05
        let reduced = RouteDisplay.sampled(points,limit:10)
        XCTAssertTrue(reduced.contains { $0.id == points[25].id })
        XCTAssertEqual(points.count,100)
    }
    func testOverviewZoomsInWhenFlightOccupiesOnlySmallPartOfAvailableMap() throws {
        // Reduced from the real-flight simulator's projected bounds; no personal coordinates.
        let fit = try XCTUnwrap(RouteViewportFit.adjustment(points: [SIMD2(580.6,244.8),SIMD2(749.2,514.3)],
            minimum: SIMD2(410,95), maximum: SIMD2(1072,642)))
        XCTAssertLessThan(fit.scale, 0.6)
    }
    func testOverviewTranslationDoesNotNeedlesslyZoomOut() throws {
        let fit = try XCTUnwrap(RouteViewportFit.adjustment(points: [SIMD2(0.0,100),SIMD2(460,500)],
            minimum: SIMD2(100,100), maximum: SIMD2(600,600)))
        XCTAssertEqual(fit.scale, 1)
        XCTAssertEqual(fit.centerOffset, SIMD2(-120,-50))
    }
    func testOverviewContainsGroundAndHeightAndStopsOnceFitted() throws {
        let fit = try XCTUnwrap(RouteViewportFit.adjustment(points: [SIMD2(100.0,-200),SIMD2(500,800)],
            minimum: SIMD2(100,100), maximum: SIMD2(600,600)))
        XCTAssertEqual(fit.scale, 2)
        XCTAssertNil(RouteViewportFit.adjustment(points: [SIMD2(120.0,120),SIMD2(580,580)],
            minimum: SIMD2(100,100), maximum: SIMD2(600,600)))
        XCTAssertNil(RouteViewportFit.adjustment(points: [.zero], minimum: .zero, maximum: .zero))
    }
    func testHeightExaggerationIsUniformAndNeverChangesAltitudeReadings() {
        let points = [point(118,-20),point(118.01,0),point(118.02,11000),point(118.03,nil)]
        let scene = RouteScene(points: points, altitudeReference: "MSL", heightScale: 10)
        XCTAssertEqual(scene.vertices.map(\.position.z), [-200,0,110000])
        XCTAssertEqual(scene.vertices.map { $0.point.altitude }, [-20,0,11000])
        XCTAssertEqual(scene.vertices.map { RouteAltitudeStyle.colorHex($0.position.z / scene.altitudeScale) },
            points.prefix(3).map { RouteAltitudeStyle.colorHex($0.altitude) })
        XCTAssertEqual(scene.vertices.last?.position.x,
            RouteScene(points: points, altitudeReference: "MSL").vertices.last?.position.x)
        XCTAssertEqual(RouteScene(points: points, altitudeReference: "MSL", heightScale: .nan).altitudeScale, 1)
        XCTAssertEqual(RouteScene(points: points, altitudeReference: "MSL", heightScale: -5).altitudeScale, 1)
    }
    #if DEBUG
    func testSyntheticAltitudePreviewIsIsolatedAndHasEveryBoundary() {
        let session = DemoRoute.altitudePreview()
        XCTAssertTrue(session.isDemo); XCTAssertEqual(session.state,.finished)
        XCTAssertEqual(session.altitudeReference,"MSL")
        XCTAssertTrue(session.points.contains { $0.altitude == nil })
        XCTAssertTrue(session.points.contains { $0.estimated == true })
        XCTAssertEqual(Set(session.points.map(\.segment)).count,2)
        let scene = RouteScene(points:session.points,altitudeReference:session.altitudeReference)
        XCTAssertEqual(scene.maximumHeight,12000); XCTAssertEqual(scene.minimumHeight,-120)
    }

    #endif

}
