import XCTest
@testable import AntiscopeCore

final class RecordingTests: XCTestCase {
    let date = Date(timeIntervalSince1970:10000)
    func point(_ seconds:Double,_ lon:Double = 118,accuracy:Double = 5) -> TrackPoint { TrackPoint(timestamp:date.addingTimeInterval(seconds),coordinate:Coordinate(32,lon),altitude:20,speed:3,horizontalAccuracy:accuracy) }
    func testDistanceAtEquatorAndDateline() {
        XCTAssertEqual(Coordinate(0,0).distance(to:Coordinate(0,1)),111195,accuracy:1)
        XCTAssertLessThan(Coordinate(0,179.999).distance(to:Coordinate(0,-179.999)),225)
    }
    func testRejectsInvalidStaleOutOfOrderAndTeleportFixes() {
        var s = TrackSession(title:"t",mode:.walking,startedAt:date)
        XCTAssertNil(s.ingest(point(0,accuracy:100),now:date))
        XCTAssertNotNil(s.ingest(point(0),now:date))
        XCTAssertNil(s.ingest(point(0),now:date))
        XCTAssertNil(s.ingest(point(1,130),now:date.addingTimeInterval(1)))
        XCTAssertNil(s.ingest(point(1),now:date.addingTimeInterval(100)))
        XCTAssertEqual(s.points.count,1)
    }
    func testPauseExcludesTimeAndDistanceAndCreatesSeparateGPXSegments() {
        var s = TrackSession(title:"A&B <ride>",mode:.cycling,startedAt:date)
        _ = s.ingest(point(0),now:date); _ = s.ingest(point(5,118.0001),now:date.addingTimeInterval(5))
        let distance = s.distance
        s.pause(at:date.addingTimeInterval(10))
        XCTAssertNil(s.ingest(point(20,118.02),now:date.addingTimeInterval(20)))
        s.resume(at:date.addingTimeInterval(100))
        XCTAssertNil(s.ingest(point(99,118.02),now:date.addingTimeInterval(100)))
        _ = s.ingest(point(100,119),now:date.addingTimeInterval(100))
        s.finish(at:date.addingTimeInterval(110))
        XCTAssertEqual(s.duration(),20); XCTAssertEqual(s.distance,distance); XCTAssertEqual(s.segments.count,2)
        let xml = TrackExport.gpx(s)
        XCTAssertTrue(xml.contains("A&amp;B &lt;ride&gt;")); XCTAssertEqual(xml.components(separatedBy:"<trkseg>").count,3)
    }
    func testSignalGapCreatesSegmentWithoutAddingDistance() {
        var s = TrackSession(title:"t",mode:.driving,startedAt:date)
        _ = s.ingest(point(0),now:date); _ = s.ingest(point(30,120),now:date.addingTimeInterval(30))
        XCTAssertEqual(s.distance,0); XCTAssertEqual(s.segments.count,2)
    }
    func testSlowWalkingAccumulatesRatherThanDiscardingEverySmallStep() {
        var s = TrackSession(title:"walk",mode:.walking,startedAt:date)
        for i in 0...12 {
            _ = s.ingest(point(Double(i),118+Double(i)*0.000012),now:date.addingTimeInterval(Double(i)))
        }
        XCTAssertGreaterThan(s.distance,10)
        XCTAssertLessThan(s.distance,16)
    }
    func testJournalSurvivesTruncatedTailAndCanResume() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:dir) }
        let store = try TrackStore(directory:dir)
        var s = TrackSession(title:"survivor",mode:.walking,startedAt:date)
        try store.saveMetadata(s)
        let accepted = s.ingest(point(5),now:date.addingTimeInterval(5))!
        try store.appendPoint(accepted,session:s)
        let path = dir.appendingPathComponent(s.id.uuidString).appendingPathExtension("jsonl")
        let handle = try FileHandle(forWritingTo:path); try handle.seekToEnd(); try handle.write(contentsOf:Data("{broken".utf8)); try handle.close()
        let loaded = try store.load()
        XCTAssertEqual(loaded.sessions.first?.points.count,1); XCTAssertEqual(loaded.sessions.first?.state,.paused)
        XCTAssertEqual(loaded.sessions.first?.duration(),5)
        var recovered = loaded.sessions[0]; recovered.resume(at:date.addingTimeInterval(50)); try store.saveMetadata(recovered)
        let p = recovered.ingest(point(51,119),now:date.addingTimeInterval(51))!
        try store.appendPoint(p,session:recovered)
        let reloaded = try store.load(); XCTAssertEqual(reloaded.sessions[0].segments.count,2)
    }
    func testUnknownMeasurementsRemainMissingAndDemoIsExplicit() {
        var s = TrackSession(title:"t",mode:.walking,startedAt:date)
        var p = point(0); p.speed = -1; p.altitude = .nan; p.heading = -1
        let result = s.ingest(p,now:date)
        XCTAssertNil(result?.speed); XCTAssertNil(result?.altitude); XCTAssertNil(result?.heading)
        let demo = DemoRoute.make(); XCTAssertTrue(demo.isDemo); XCTAssertEqual(demo.points.count,241)
    }
    func testDisplaySamplingPreservesSegmentBoundariesAndOriginalData() {
        var points = (0..<10_000).map { point(Double($0),118+Double($0)*0.00001) }
        for i in 5023..<points.count { points[i].segment = 1 }
        let reduced = RouteDisplay.sampled(points,limit:900)
        XCTAssertLessThan(reduced.count,1000)
        XCTAssertTrue(reduced.contains(where: { $0.id == points[5022].id }))
        XCTAssertTrue(reduced.contains(where: { $0.id == points[5023].id }))
        XCTAssertEqual(reduced.first?.id,points.first?.id); XCTAssertEqual(reduced.last?.id,points.last?.id)
        XCTAssertEqual(points.count,10_000)
    }
}
