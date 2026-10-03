import Foundation

public struct VectorENU: Codable, Equatable, Sendable {
    public var east: Double
    public var north: Double
    public var up: Double
    public init(east: Double, north: Double, up: Double) { self.east = east; self.north = north; self.up = up }
    public var horizontalSpeed: Double { hypot(east, north) }
    public var isFinite: Bool { east.isFinite && north.isFinite && up.isFinite }
}
public struct TrackProvenance: Codable, Equatable, Sendable {
    public var sourceID: UUID?
    public var fingerprint: String?
    public var originalState: RecordingState?
}
public enum NavigationStatus: String, Codable, Sendable { case uninitialized, corrected, predicted, invalid }
public struct InertialState: Codable, Equatable, Sendable {
    public var coordinate: Coordinate?
    public var speedMps: Double?
    public var velocityENU: VectorENU?
    public var accelerationENU: VectorENU?
    public var altitudeM: Double?
    public var bearingDeg: Double?
    public var bearingSource: String?
    public var bearingReference: String?
    public var status: NavigationStatus = .uninitialized
    public var lastCorrectionAt: Date?
    public var predictionAgeSeconds: Double?
    public var horizontalUncertaintyM: Double?
    public init() {}
}
public struct GPSObservation: Codable, Equatable, Sendable {
    public var coordinate: Coordinate?
    public var speedMps: Double?
    public var altitudeM: Double?
    public var observedAt: Date?
    public var horizontalAccuracyM: Double?
    public var verticalAccuracyM: Double?
    public var source: String?
    public var courseDeg: Double?
    public var deviceHeadingDeg: Double?
    public var deviceHeadingReference: String?
    public var usableForRoute: Bool?
    public init() {}
    /// System fields are independently valid; a failed horizontal fix must not erase valid altitude/speed.
    public init(measuredCoordinate: Coordinate, observedAt: Date, horizontalAccuracyM: Double,
                altitudeM: Double, verticalAccuracyM: Double, speedMps: Double, courseDeg: Double) {
        self.observedAt = observedAt; source = "core_location"
        self.horizontalAccuracyM = horizontalAccuracyM.isFinite && horizontalAccuracyM >= 0 ? horizontalAccuracyM : nil
        coordinate = self.horizontalAccuracyM != nil && measuredCoordinate.isValid ? measuredCoordinate : nil
        self.verticalAccuracyM = verticalAccuracyM.isFinite && verticalAccuracyM >= 0 ? verticalAccuracyM : nil
        self.altitudeM = self.verticalAccuracyM != nil && altitudeM.isFinite ? altitudeM : nil
        self.speedMps = speedMps.isFinite && speedMps >= 0 ? speedMps : nil
        self.courseDeg = courseDeg.isFinite && (0..<360).contains(courseDeg) ? courseDeg : nil
    }
    public init(point: TrackPoint, source: String = "core_location") {
        coordinate = point.coordinate; speedMps = point.speed; altitudeM = point.altitude
        observedAt = point.timestamp; horizontalAccuracyM = point.horizontalAccuracy
        verticalAccuracyM = point.verticalAccuracy; courseDeg = point.course; deviceHeadingDeg = point.heading; self.source = source
    }
    public func fresh(at date: Date, limit: Double = 2) -> GPSObservation {
        guard let observedAt, (-0.25...limit).contains(date.timeIntervalSince(observedAt)) else { return GPSObservation() }
        return self
    }
}
public struct NavigationSample: Codable, Equatable, Sendable {
    public var recordType = "sample"
    public var sequence: Int
    public var segmentId: Int
    public var timestamp: Date?
    public var inertial: InertialState
    public var gps: GPSObservation
    public var rawMotion: [MotionSample]
    public var rawLocations: [GPSObservation]?
    public var cumulativeDistanceM: Double?
    public var id: UUID
    public init(sequence: Int, segmentId: Int, timestamp: Date?, inertial: InertialState = .init(), gps: GPSObservation = .init(), rawMotion: [MotionSample] = [], id: UUID = UUID()) {
        self.sequence = sequence; self.segmentId = segmentId; self.timestamp = timestamp
        self.inertial = inertial; self.gps = gps; self.rawMotion = rawMotion; self.id = id
    }
    public var usesInertial: Bool { [.corrected, .predicted].contains(inertial.status) && inertial.coordinate != nil }
    public var displayCoordinate: Coordinate? { usesInertial ? inertial.coordinate : (gps.usableForRoute == false ? nil : gps.coordinate) }
    public var displayAltitude: Double? { usesInertial ? inertial.altitudeM : gps.altitudeM }
    public var displayPoint: TrackPoint? {
        guard let coordinate = displayCoordinate else { return nil }
        var point = TrackPoint(timestamp: timestamp, coordinate: coordinate, altitude: displayAltitude,
            speed: usesInertial ? inertial.speedMps : gps.speedMps,
            course: usesInertial ? inertial.bearingDeg : gps.courseDeg,
            horizontalAccuracy: usesInertial ? inertial.horizontalUncertaintyM : gps.horizontalAccuracyM,
            verticalAccuracy: gps.verticalAccuracyM, segment: segmentId)
        point.id = id; point.heading = gps.deviceHeadingDeg; point.estimated = usesInertial
        return point
    }
}
public struct TrackMetadata: Codable, Sendable {
    public var recordType = "metadata"
    public var format = "altiscope.track"
    public var schemaVersion = 1
    public var sessionId: UUID
    public var travelMode: TravelMode?
    public var name: String
    public var notes: String
    public var coordinateReference = "WGS84"
    public var vectorFrame = "ENU"
    public var altitudeReference: String
    public var units = ["altitude": "m", "speed": "m/s", "acceleration": "m/s²", "angle": "deg"]
    public var startedAt: Date?
    public var endedAt: Date?
    public var state: RecordingState
    public var activeSeconds: Double?
    public var intervalStartedAt: Date?
    public var segmentId: Int
    public var distanceM: Double
    public var isDemo: Bool
    public var provenance: TrackProvenance?
    public var legacyMotion: [MotionSample]
    public init(session: TrackSession) {
        sessionId = session.id; travelMode = session.mode; name = session.title; notes = session.notes
        altitudeReference = session.altitudeReference ?? "MSL"
        startedAt = session.startedAt; endedAt = session.endedAt; state = session.state
        activeSeconds = session.durationKnown == false ? nil : session.activeSeconds
        intervalStartedAt = session.intervalStartedAt; segmentId = session.segment
        distanceM = session.distance; isDemo = session.isDemo; provenance = session.provenance
        legacyMotion = session.legacyMotion ?? (session.navigationSamples == nil ? session.motion : [])
    }
}
public struct TrackDocument: Codable, Sendable {
    public var metadata: TrackMetadata
    public var samples: [NavigationSample]
    public init(session: TrackSession) {
        metadata = TrackMetadata(session: session)
        samples = session.navigationSamples ?? session.points.enumerated().map {
            NavigationSample(sequence: $0.offset + 1, segmentId: $0.element.segment, timestamp: $0.element.timestamp,
                             gps: GPSObservation(point: $0.element, source: session.isDemo ? "demo" : "legacy_core_location"), id: $0.element.id)
        }
    }
    public init(metadata: TrackMetadata, samples: [NavigationSample]) { self.metadata = metadata; self.samples = samples }
    public func session() -> TrackSession {
        var session = TrackSession(title: metadata.name, mode: metadata.travelMode ?? .walking)
        session.id = metadata.sessionId; session.startedAt = metadata.startedAt; session.endedAt = metadata.endedAt
        session.state = metadata.state; session.activeSeconds = metadata.activeSeconds ?? 0
        session.durationKnown = metadata.activeSeconds != nil; session.intervalStartedAt = metadata.intervalStartedAt
        session.segment = max(metadata.segmentId, samples.last?.segmentId ?? 0)
        session.notes = metadata.notes; session.isDemo = metadata.isDemo; session.navigationSamples = samples
        session.provenance = metadata.provenance; session.altitudeReference = metadata.altitudeReference
        session.points = []
        var previousSample: NavigationSample?
        for sample in samples {
            if var point = sample.displayPoint {
                let continuing = previousSample?.displayCoordinate != nil && previousSample?.segmentId == sample.segmentId
                point.segment = continuing ? (session.points.last?.segment ?? 0) : (session.points.last.map { $0.segment + 1 } ?? sample.segmentId)
                session.points.append(point)
            }
            previousSample = sample
        }
        session.legacyMotion = metadata.legacyMotion
        session.motion = metadata.legacyMotion + samples.flatMap(\.rawMotion)
        // Latest header distance is a checkpoint. Samples after it must survive an interrupted recording.
        session.distance = samples.last?.cumulativeDistanceM ?? metadata.distanceM
        session.distanceAnchor = session.points.last
        return session
    }
    public static func distance(_ samples: [NavigationSample]) -> Double {
        var result = 0.0
        var previous: NavigationSample?
        for sample in samples {
            defer { previous = sample.displayCoordinate == nil ? nil : sample }
            guard let point = sample.displayCoordinate, let last = previous, last.segmentId == sample.segmentId,
                  let origin = last.displayCoordinate else { continue }
            result += origin.distance(to: point)
        }
        return result
    }
    public func validate() throws {
        let m = metadata
        guard m.recordType == "metadata", m.format == "altiscope.track", m.schemaVersion == 1 else { throw TrackFileError.invalid("不支持的记录版本") }
        guard m.coordinateReference == "WGS84", m.vectorFrame == "ENU", ["MSL", "unknown"].contains(m.altitudeReference),
              m.units == ["altitude":"m", "speed":"m/s", "acceleration":"m/s²", "angle":"deg"] else { throw TrackFileError.invalid("坐标系、向量参考系、单位或高度基准不受支持") }
        guard m.distanceM.isFinite, m.distanceM >= 0, m.activeSeconds.map({ $0.isFinite && $0 >= 0 }) ?? true, m.segmentId >= 0 else { throw TrackFileError.invalid("无效的会话统计") }
        guard samples.count <= TrackCodec.maximumSamples else { throw TrackFileError.invalid("采样数量超过上限") }
        var lastSequence = 0, lastSegment = -1
        var ids = Set<UUID>()
        for sample in samples {
            guard sample.recordType == "sample", sample.sequence > lastSequence, sample.segmentId >= lastSegment,
                  sample.segmentId >= 0, ids.insert(sample.id).inserted else { throw TrackFileError.invalid("采样序号、分段或 ID 重复/乱序") }
            lastSequence = sample.sequence; lastSegment = sample.segmentId
            guard sample.cumulativeDistanceM.map({ $0.isFinite && $0 >= 0 }) ?? true else { throw TrackFileError.invalid("无效累计距离") }
            let i = sample.inertial, g = sample.gps
            for coordinate in [i.coordinate, g.coordinate].compactMap({ $0 }) {
                guard coordinate.isValid else { throw TrackFileError.invalid("经纬度超出范围") }
            }
            let numbers = [i.speedMps, i.altitudeM, i.bearingDeg, i.predictionAgeSeconds, i.horizontalUncertaintyM, g.speedMps, g.altitudeM, g.horizontalAccuracyM, g.verticalAccuracyM, g.courseDeg].compactMap { $0 }
            guard numbers.allSatisfy(\.isFinite), [i.velocityENU, i.accelerationENU].compactMap({ $0 }).allSatisfy(\.isFinite),
                  [i.speedMps, i.predictionAgeSeconds, i.horizontalUncertaintyM, g.speedMps, g.horizontalAccuracyM, g.verticalAccuracyM].compactMap({ $0 }).allSatisfy({ $0 >= 0 }),
                  [i.bearingDeg, g.courseDeg, g.deviceHeadingDeg].compactMap({ $0 }).allSatisfy({ (0..<360).contains($0) }) else { throw TrackFileError.invalid("采样含非法数值") }
            guard i.bearingSource.map({ ["previous_velocity", "compass"].contains($0) }) ?? true,
                  i.bearingReference.map({ ["true_north", "magnetic_north"].contains($0) }) ?? true,
                  (i.bearingDeg == nil) == (i.bearingSource == nil), (i.bearingDeg == nil) == (i.bearingReference == nil) else { throw TrackFileError.invalid("方向角来源或北向基准无效") }
            for observation in [sample.gps] + (sample.rawLocations ?? []) {
                guard observation.coordinate.map(\.isValid) ?? true,
                      [observation.speedMps, observation.horizontalAccuracyM, observation.verticalAccuracyM].compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 >= 0 }),
                      observation.altitudeM.map(\.isFinite) ?? true,
                      [observation.courseDeg, observation.deviceHeadingDeg].compactMap({ $0 }).allSatisfy({ $0.isFinite && (0..<360).contains($0) }),
                      observation.deviceHeadingReference.map({ ["true_north", "magnetic_north"].contains($0) }) ?? true else { throw TrackFileError.invalid("原始定位观测含无效数值") }
            }
            try TrackCodec.validateMotion(sample.rawMotion)
        }
        try TrackCodec.validateMotion(m.legacyMotion)
    }
}
public enum TrackFileError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { switch self { case .invalid(let text): return text } }
}
public enum TrackCodec {
    public static let maximumBytes = 64 * 1024 * 1024
    public static let maximumSamples = 200_000
    public static func dateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
    public static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]; return formatter.date(from: text)
    }
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer(); try container.encode(dateString(date))
        }; return encoder
    }
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer(); let text = try container.decode(String.self)
            guard let date = date(text) else { throw TrackFileError.invalid("无效 UTC 时间：\(text)") }; return date
        }; return decoder
    }
    public static func json(_ document: TrackDocument) throws -> Data { try document.validate(); return try encoder().encode(document) }
    public static func jsonl(_ document: TrackDocument) throws -> Data {
        try document.validate()
        var data = try encoder().encode(document.metadata); data.append(10)
        for sample in document.samples { data.append(try encoder().encode(sample)); data.append(10) }
        return data
    }
    static func validateMotion(_ values: [MotionSample]) throws {
        guard values.allSatisfy({ value in
            [value.x, value.y, value.z].allSatisfy(\.isFinite) &&
            (value.monotonicTime.map { $0.isFinite && $0 >= 0 } ?? true) &&
            (value.rotationMatrix.map { $0.count == 9 && $0.allSatisfy(\.isFinite) } ?? true) &&
            (value.rotationRate.map { $0.count == 3 && $0.allSatisfy(\.isFinite) } ?? true)
        }) else { throw TrackFileError.invalid("无效的原始运动采样") }
    }
}
extension TrackSession {
    public mutating func appendNavigation(_ sample: NavigationSample) {
        if navigationSamples == nil { navigationSamples = TrackDocument(session: self).samples }
        if let previous = navigationSamples?.last, previous.segmentId == sample.segmentId,
           let a = previous.displayCoordinate, let b = sample.displayCoordinate { distance += a.distance(to: b) }
        let previous = navigationSamples?.last
        if var point = sample.displayPoint {
            let continuing = previous?.displayCoordinate != nil && previous?.segmentId == sample.segmentId
            point.segment = continuing ? (points.last?.segment ?? 0) : (points.last.map { $0.segment + 1 } ?? sample.segmentId)
            points.append(point)
        }
        navigationSamples?.append(sample); segment = sample.segmentId
        motion.append(contentsOf: sample.rawMotion)
    }
}

extension InertialState {
    enum CodingKeys: String, CodingKey { case coordinate, speedMps, velocityENU, accelerationENU, altitudeM, bearingDeg, bearingSource, bearingReference, status, lastCorrectionAt, predictionAgeSeconds, horizontalUncertaintyM }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(coordinate, forKey: .coordinate)
        try container.encode(speedMps, forKey: .speedMps)
        try container.encode(velocityENU, forKey: .velocityENU)
        try container.encode(accelerationENU, forKey: .accelerationENU)
        try container.encode(altitudeM, forKey: .altitudeM)
        try container.encode(bearingDeg, forKey: .bearingDeg)
        try container.encode(bearingSource, forKey: .bearingSource)
        try container.encode(bearingReference, forKey: .bearingReference)
        try container.encode(status, forKey: .status)
        try container.encode(lastCorrectionAt, forKey: .lastCorrectionAt)
        try container.encode(predictionAgeSeconds, forKey: .predictionAgeSeconds)
        try container.encode(horizontalUncertaintyM, forKey: .horizontalUncertaintyM)
    }
}

extension GPSObservation {
    enum CodingKeys: String, CodingKey { case coordinate, speedMps, altitudeM, observedAt, horizontalAccuracyM, verticalAccuracyM, source, courseDeg, deviceHeadingDeg, deviceHeadingReference, usableForRoute }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(coordinate, forKey: .coordinate)
        try container.encode(speedMps, forKey: .speedMps)
        try container.encode(altitudeM, forKey: .altitudeM)
        try container.encode(observedAt, forKey: .observedAt)
        try container.encode(horizontalAccuracyM, forKey: .horizontalAccuracyM)
        try container.encode(verticalAccuracyM, forKey: .verticalAccuracyM)
        try container.encode(source, forKey: .source)
        try container.encode(courseDeg, forKey: .courseDeg)
        try container.encode(deviceHeadingDeg, forKey: .deviceHeadingDeg)
        try container.encode(deviceHeadingReference, forKey: .deviceHeadingReference)
        try container.encode(usableForRoute, forKey: .usableForRoute)
    }
}

extension NavigationSample {
    enum CodingKeys: String, CodingKey { case recordType, sequence, segmentId, timestamp, inertial, gps, rawMotion, rawLocations, cumulativeDistanceM, id }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(recordType, forKey: .recordType)
        try container.encode(sequence, forKey: .sequence)
        try container.encode(segmentId, forKey: .segmentId)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(inertial, forKey: .inertial)
        try container.encode(gps, forKey: .gps)
        try container.encode(rawMotion, forKey: .rawMotion)
        try container.encode(rawLocations, forKey: .rawLocations)
        try container.encode(cumulativeDistanceM, forKey: .cumulativeDistanceM)
        try container.encode(id, forKey: .id)
    }
}

extension TrackMetadata {
    enum CodingKeys: String, CodingKey { case recordType, format, schemaVersion, sessionId, travelMode, name, notes, coordinateReference, vectorFrame, altitudeReference, units, startedAt, endedAt, state, activeSeconds, intervalStartedAt, segmentId, distanceM, isDemo, provenance, legacyMotion }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(recordType, forKey: .recordType)
        try container.encode(format, forKey: .format)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(travelMode, forKey: .travelMode)
        try container.encode(name, forKey: .name)
        try container.encode(notes, forKey: .notes)
        try container.encode(coordinateReference, forKey: .coordinateReference)
        try container.encode(vectorFrame, forKey: .vectorFrame)
        try container.encode(altitudeReference, forKey: .altitudeReference)
        try container.encode(units, forKey: .units)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(endedAt, forKey: .endedAt)
        try container.encode(state, forKey: .state)
        try container.encode(activeSeconds, forKey: .activeSeconds)
        try container.encode(intervalStartedAt, forKey: .intervalStartedAt)
        try container.encode(segmentId, forKey: .segmentId)
        try container.encode(distanceM, forKey: .distanceM)
        try container.encode(isDemo, forKey: .isDemo)
        try container.encode(provenance, forKey: .provenance)
        try container.encode(legacyMotion, forKey: .legacyMotion)
    }
}
