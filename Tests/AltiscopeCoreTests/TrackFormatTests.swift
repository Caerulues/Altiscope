import XCTest
@testable import AltiscopeCore

final class TrackFormatTests: XCTestCase {
    let date = Date(timeIntervalSince1970: 1_791_000_000.125)
    func fixture() -> TrackSession {
        var session = TrackSession(title: "中文 & <旅程>", mode: .flight, startedAt: date)
        session.notes = "第一行\n第二行 \"笔记\""; session.state = .finished; session.intervalStartedAt = nil
        session.endedAt = date.addingTimeInterval(2); session.navigationSamples = []
        var gps = GPSObservation(); gps.coordinate = Coordinate(30, 120); gps.observedAt = date.addingTimeInterval(-0.125)
        gps.speedMps = 7; gps.altitudeM = -20; gps.source = "core_location"; gps.horizontalAccuracyM = 5
        var inertial = InertialState(); inertial.coordinate = gps.coordinate; inertial.altitudeM = -19; inertial.status = .corrected
        inertial.speedMps = 7; inertial.velocityENU = VectorENU(east: 7, north: 0, up: 0)
        inertial.bearingDeg = 90; inertial.bearingSource = "previous_velocity"; inertial.bearingReference = "true_north"
        inertial.lastCorrectionAt = gps.observedAt; inertial.predictionAgeSeconds = 0.125
        var motion = MotionSample(timestamp: date, x: 0, y: 0, z: 0); motion.monotonicTime = 50
        motion.rotationMatrix = [1,0,0,0,1,0,0,0,1]; motion.rotationRate = [0,0,0]; motion.attitudeReference = "north_west_up"
        session.appendNavigation(NavigationSample(sequence: 1, segmentId: 0, timestamp: date, inertial: inertial, gps: gps, rawMotion: [motion]))
        session.appendNavigation(NavigationSample(sequence: 2, segmentId: 0, timestamp: date.addingTimeInterval(1)))
        var external = GPSObservation(); external.coordinate = Coordinate(30.01, 120.01); external.source = "external_gpx_unknown"
        session.appendNavigation(NavigationSample(sequence: 3, segmentId: 1, timestamp: nil, gps: external))
        return session
    }
    func testJSONJSONLAndGPXRoundTripPreserveNullsProvenanceAndSegments() throws {
        let session = fixture()
        let original = TrackDocument(session: session)
        for (ext, data) in [("json", try TrackCodec.json(original)), ("jsonl", try TrackCodec.jsonl(original)), ("gpx", Data(TrackExport.gpx(session).utf8))] {
            let result = try TrackImport.read(data, extension: ext, filename: "fallback")
            let document = try XCTUnwrap(result.documents.first)
            XCTAssertEqual(document.samples, original.samples, ext)
            XCTAssertEqual(document.metadata.name, original.metadata.name)
            XCTAssertEqual(document.metadata.notes, original.metadata.notes)
            XCTAssertEqual(document.metadata.travelMode, .flight)
            XCTAssertEqual(document.session().points.count, 2)
            XCTAssertNil(document.samples[1].gps.coordinate)
            XCTAssertNil(document.samples[2].timestamp)
        }
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: TrackCodec.json(original)) as? [String: Any])
        let samples = try XCTUnwrap(object["samples"] as? [[String: Any]])
        let gps = try XCTUnwrap(samples[1]["gps"] as? [String: Any])
        XCTAssertTrue(gps["coordinate"] is NSNull); XCTAssertTrue(gps["observedAt"] is NSNull)
        XCTAssertTrue(samples[2]["timestamp"] is NSNull)
        XCTAssertTrue(TrackExport.gpx(fixture()).contains("missing=\"true\""))
    }
    func testPlainMultiTrackGPXAndRouteDoNotInventTimesOrInertialValues() throws {
        let xml = """
        <gpx xmlns="http://www.topografix.com/GPX/1/1" version="1.1" creator="test">
        <rte><name>route</name><rtept lat="0" lon="0"/><rtept lat="0" lon="1"/></rte>
        <trk><name>轨迹一</name><trkseg><trkpt lat="32" lon="118"><ele>-10</ele></trkpt></trkseg><trkseg><trkpt lat="32.1" lon="118.1"/></trkseg></trk>
        </gpx>
        """
        let result = try TrackImport.read(Data(xml.utf8), extension: "gpx", filename: "example")
        XCTAssertEqual(result.documents.count, 2)
        XCTAssertEqual(result.documents[0].samples[0].gps.coordinate, Coordinate(0,0))
        XCTAssertEqual(result.documents[1].samples.map(\.segmentId), [0,1])
        XCTAssertNil(result.documents[0].metadata.startedAt); XCTAssertNil(result.documents[0].metadata.activeSeconds)
        XCTAssertNil(result.documents[0].metadata.travelMode)
        XCTAssertEqual(result.documents[1].metadata.altitudeReference, "unknown")
        XCTAssertNil(result.documents[1].samples[0].inertial.coordinate)
        XCTAssertEqual(result.documents[1].samples[0].gps.source, "external_gpx_unknown")
    }
    func testMalformedMiddleLineNotSilentlySkippedAndOnlyIncompleteTailRecovered() throws {
        let data = try TrackCodec.jsonl(TrackDocument(session: fixture()))
        var tail = data; tail.append(Data("{\"recordType\":".utf8))
        let recovered = try TrackImport.decodeJSONL(tail, recoverTail: true)
        XCTAssertEqual(recovered.recoveredLength, data.count); XCTAssertEqual(recovered.documents[0].samples.count, 3)
        var middle = data; middle.append(Data("{broken\n{}\n".utf8))
        XCTAssertThrowsError(try TrackImport.decodeJSONL(middle, recoverTail: true))
        var semantic = data; semantic.append(Data("{}".utf8))
        XCTAssertThrowsError(try TrackImport.decodeJSONL(semantic, recoverTail: true))
    }
    func testRejectsXMLExternalEntitiesInvalidCoordinatesVersionsAndConflictingProjection() throws {
        for xml in [
            "<!DOCTYPE gpx [<!ENTITY secret SYSTEM 'file:///etc/passwd'>]><gpx xmlns='http://www.topografix.com/GPX/1/1' version='1.1'><trk><name>&secret;</name></trk></gpx>",
            "<gpx xmlns='http://www.topografix.com/GPX/1/1' version='1.0'><trk/></gpx>",
            "<gpx xmlns='http://www.topografix.com/GPX/1/1' version='1.1'><trk><trkseg><trkpt lat='91' lon='0'/></trkseg></trk></gpx>",
            "<gpx xmlns='http://www.topografix.com/GPX/1/1' version='1.1'><wpt lat='0' lon='0'/></gpx>",
            TrackExport.gpx(fixture()).replacingOccurrences(of: "lat=\"30.0\"", with: "lat=\"31.0\"")
        ] { XCTAssertThrowsError(try TrackImport.read(Data(xml.utf8), extension: "gpx", filename: "bad")) }
    }
    func testHeaderEditAndDeletePreserveOtherRecordsAndSampleBytes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try TrackStore(directory: directory); var session = fixture()
        try store.saveMetadata(session)
        let file = directory.appendingPathComponent(session.id.uuidString + ".jsonl")
        let original = try Data(contentsOf: file).split(separator: 10).dropFirst().map { Data($0) }
        session.title = String(repeating: "长名称", count: 1000); session.mode = .cycling; session.notes += "\n新增"
        try store.saveMetadata(session)
        XCTAssertEqual(try Data(contentsOf: file).split(separator: 10).dropFirst().map { Data($0) }, original)
        let loaded = try store.load(); XCTAssertEqual(loaded.sessions[0].title, session.title); XCTAssertEqual(loaded.sessions[0].mode, .cycling)
        var second = fixture(); second.id = UUID(); try store.saveMetadata(second)
        try store.delete(session.id)
        XCTAssertEqual(try store.load().sessions.map(\.id), [second.id])
    }
    func testLegacyJSONAndJSONLEventsMigrateWithBackup() throws {
        var session = TrackSession(title: "旧记录", mode: .walking, startedAt: date)
        let point = TrackPoint(timestamp: date, coordinate: Coordinate(32,118), speed: 0, heading: 123)
        session.motion = [MotionSample(timestamp: date, x: 1, y: 2, z: 3)]
        session.points = [point]; session.finish(at: date.addingTimeInterval(5)); session.distance = 123
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        let oldJSON = try encoder.encode(session)
        let result = try TrackImport.read(oldJSON, extension: "json", filename: "old")
        XCTAssertEqual(result.documents[0].samples[0].gps.coordinate, point.coordinate)
        XCTAssertNil(result.documents[0].samples[0].inertial.coordinate)
        XCTAssertEqual(result.documents[0].session().distance, 123)
        XCTAssertEqual(result.documents[0].session().points[0].heading, 123)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try TrackStore(directory: directory)
        let file = directory.appendingPathComponent(session.id.uuidString + ".jsonl")
        var metadata = session; metadata.points = []
        var bytes = try encoder.encode(TrackStore.LegacyEvent(metadata: metadata)); bytes.append(10)
        bytes.append(try encoder.encode(TrackStore.LegacyEvent(point: point, distance: 123))); bytes.append(10)
        try bytes.write(to: file)
        var loaded = try XCTUnwrap(store.load().sessions.first); loaded.title = "迁移后"
        try store.saveMetadata(loaded)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.appendingPathExtension("legacy-backup").path))
        XCTAssertEqual(try Data(contentsOf: file.appendingPathExtension("legacy-backup")), bytes)
        XCTAssertEqual(try store.load().sessions[0].points[0].coordinate, point.coordinate)
        XCTAssertEqual(try store.load().sessions[0].motion, session.motion)
    }
    func testImportCopiesIDsDoesNotResumeRecordingAndRollsBackFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try TrackStore(directory: directory)
        var document = TrackDocument(session: fixture()); document.metadata.state = .recording
        let imported = try store.importDocuments([document, document])
        XCTAssertEqual(Set(imported.map(\.id)).count, 2); XCTAssertNotEqual(imported[0].id, document.metadata.sessionId)
        XCTAssertEqual(imported[0].provenance?.originalState, .recording); XCTAssertEqual(imported[0].state, .finished)
        var invalid = document; invalid.metadata.schemaVersion = 999
        XCTAssertThrowsError(try store.importDocuments([document, invalid]))
        XCTAssertEqual(try store.load().sessions.count, 2)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasPrefix(".import") })
    }
    func testMissingPositionBreaksMapAndDistanceEvenWithinOneSourceSegment() {
        var session = fixture()
        session.navigationSamples?[2].segmentId = 0
        let document = TrackDocument(session: session)
        XCTAssertEqual(document.session().segments.count, 2)
        XCTAssertEqual(TrackDocument.distance(document.samples), 0)
    }
    func testLongHeaderRewriteFailureDoesNotReplaceExistingFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try TrackStore(directory: directory)
        var session = fixture()
        let template = session.navigationSamples![0]
        session.navigationSamples = (1...5000).map { index in
            var sample = template; sample.id = UUID(); sample.sequence = index; sample.timestamp = date.addingTimeInterval(Double(index)); return sample
        }
        try store.saveMetadata(session)
        let file = directory.appendingPathComponent(session.id.uuidString + ".jsonl")
        let original = try Data(contentsOf: file)
        var invalid = session; invalid.activeSeconds = .nan
        XCTAssertThrowsError(try store.saveMetadata(invalid))
        XCTAssertEqual(try Data(contentsOf: file), original)
        session.title = String(repeating: "长记录修改", count: 200)
        try store.saveMetadata(session)
        XCTAssertEqual(try store.load().sessions[0].navigationSamples?.count, 5000)
    }
    func testUnitConversionsArePhysicalAndAltitudeUnknownIsDistinct() {
        XCTAssertEqual(DisplayUnits.metric.altitude(123), 123)
        XCTAssertEqual(DisplayUnits.metric.altitude(-33.2), -33.2)
        XCTAssertEqual(DisplayUnits.metric.altitudeLabel, "m")
        XCTAssertEqual(DisplayUnits.metric.speed(10), 36)
        XCTAssertEqual(DisplayUnits.metric.speedLabel, "km/h")
        XCTAssertEqual(DisplayUnits.aviation.altitude(0.3048), 1)
        XCTAssertEqual(DisplayUnits.aviation.speed(1852.0 / 3600), 1)
        XCTAssertNotEqual(RouteAltitudeStyle.colorHex(nil), RouteAltitudeStyle.colorHex(0))
        XCTAssertEqual(RouteAltitudeStyle.colorHex(-400), RouteAltitudeStyle.colorHex(0))
    }
}
