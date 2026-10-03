import Foundation

/// Compile with Sources/AltiscopeCore/*.swift. These fixtures are entirely synthetic.
@main enum FormatFixtures {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Documentation/Formats")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let epoch = TrackCodec.date("2026-10-02T12:00:00.125Z")!
        var session = TrackSession(title: "格式样例（虚构）", mode: .cycling, startedAt: epoch)
        session.id = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        session.notes = "非实测数据\n包含估计、缺失 GPS、无坐标与未计时样本。"
        session.state = .finished; session.intervalStartedAt = nil; session.endedAt = epoch.addingTimeInterval(3)
        session.durationKnown = false; session.navigationSamples = []
        var gps = GPSObservation(); gps.coordinate = Coordinate(30,120); gps.observedAt = epoch.addingTimeInterval(-0.125)
        gps.source = "core_location"; gps.speedMps = 1; gps.altitudeM = 100; gps.horizontalAccuracyM = 5; gps.verticalAccuracyM = 3
        var inertial = InertialState(); inertial.coordinate = gps.coordinate; inertial.altitudeM = 100
        inertial.speedMps = 1; inertial.velocityENU = VectorENU(east: 1, north: 0, up: 0); inertial.accelerationENU = VectorENU(east: 0, north: 0, up: 0)
        inertial.status = .corrected; inertial.lastCorrectionAt = gps.observedAt; inertial.predictionAgeSeconds = 0.125
        inertial.bearingDeg = 90; inertial.bearingSource = "previous_velocity"; inertial.bearingReference = "true_north"
        session.appendNavigation(NavigationSample(sequence: 1, segmentId: 0, timestamp: epoch, inertial: inertial, gps: gps, id: UUID(uuidString: "22222222-2222-4222-8222-222222222221")!))
        inertial.coordinate = Coordinate(30, 120.00001); inertial.status = .predicted; inertial.predictionAgeSeconds = 1.125
        session.appendNavigation(NavigationSample(sequence: 2, segmentId: 0, timestamp: epoch.addingTimeInterval(1), inertial: inertial, id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!))
        session.appendNavigation(NavigationSample(sequence: 3, segmentId: 1, timestamp: epoch.addingTimeInterval(2), id: UUID(uuidString: "22222222-2222-4222-8222-222222222223")!))
        gps = GPSObservation(); gps.coordinate = Coordinate(30.001,120.001); gps.source = "external_gpx_unknown"
        session.appendNavigation(NavigationSample(sequence: 4, segmentId: 2, timestamp: nil, gps: gps, id: UUID(uuidString: "22222222-2222-4222-8222-222222222224")!))
        let document = TrackDocument(session: session)
        for (ext, data) in [("json", try TrackCodec.json(document)), ("jsonl", try TrackCodec.jsonl(document)), ("gpx", Data(TrackExport.gpx(session).utf8))] {
            try data.write(to: output.appendingPathComponent("synthetic-track.\(ext)"))
            let decoded = try TrackImport.read(data, extension: ext, filename: "synthetic")
            guard decoded.documents[0].samples == document.samples else { throw TrackFileError.invalid("Fixture round trip failed: \(ext)") }
            print("\(ext): round trip preserved \(document.samples.count) samples")
        }
    }
}
