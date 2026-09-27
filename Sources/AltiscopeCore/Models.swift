import Foundation

public struct Coordinate: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public init(_ latitude: Double, _ longitude: Double) { self.latitude = latitude; self.longitude = longitude }
    public var isValid: Bool { latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180 }
    public func distance(to other: Coordinate) -> Double {
        let r = Double.pi / 180, a = latitude * r, b = other.latitude * r
        let h = pow(sin((b-a)/2), 2) + cos(a)*cos(b)*pow(sin((other.longitude-longitude)*r/2), 2)
        return 6_371_008.8 * 2 * atan2(sqrt(max(0,h)), sqrt(max(0,1-h)))
    }
}

public struct MotionSample: Codable, Equatable, Sendable {
    public var timestamp: Date
    /// User acceleration with gravity removed, in m/s², in device axes.
    public var x: Double
    public var y: Double
    public var z: Double
    public var magnitude: Double { sqrt(x*x+y*y+z*z) }
    public init(timestamp: Date, x: Double, y: Double, z: Double) { self.timestamp = timestamp; self.x = x; self.y = y; self.z = z }
}

public struct TrackPoint: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var timestamp: Date
    public var coordinate: Coordinate
    public var altitude: Double?
    public var speed: Double?
    public var course: Double?
    public var heading: Double?
    public var horizontalAccuracy: Double
    public var verticalAccuracy: Double?
    public var segment: Int = 0
    public init(timestamp: Date, coordinate: Coordinate, altitude: Double? = nil, speed: Double? = nil,
                course: Double? = nil, heading: Double? = nil, horizontalAccuracy: Double = 5, verticalAccuracy: Double? = nil, segment: Int = 0) {
        self.timestamp = timestamp; self.coordinate = coordinate; self.altitude = altitude; self.speed = speed
        self.course = course; self.heading = heading; self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy; self.segment = segment
    }
}

public enum RecordingState: String, Codable, Sendable { case recording, paused, finished }
public enum TravelMode: String, Codable, CaseIterable, Sendable {
    case walking, cycling, driving, flight
    public var title: String { switch self { case .walking: return "步行"; case .cycling: return "骑行"; case .driving: return "驾车"; case .flight: return "飞行" } }
    public var symbol: String { switch self { case .walking: return "figure.walk"; case .cycling: return "bicycle"; case .driving: return "car.fill"; case .flight: return "airplane" } }
}

public struct TrackSession: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var title: String
    public var mode: TravelMode
    public var startedAt: Date
    public var endedAt: Date?
    public var state: RecordingState = .recording
    public var activeSeconds: TimeInterval = 0
    public var intervalStartedAt: Date?
    public var segment: Int = 0
    public var distance: Double = 0
    public var distanceAnchor: TrackPoint?
    public var points: [TrackPoint] = []
    public var motion: [MotionSample] = []
    public var notes = ""
    public var isDemo = false
    public init(title: String, mode: TravelMode, startedAt: Date = Date()) {
        self.title = title; self.mode = mode; self.startedAt = startedAt; intervalStartedAt = startedAt
    }
    public func duration(at date: Date = Date()) -> TimeInterval {
        activeSeconds + (intervalStartedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }
    public var maxSpeed: Double? { points.compactMap(\.speed).max() }
    public var segments: [[TrackPoint]] {
        var result: [[TrackPoint]] = []
        for point in points {
            if result.last?.last?.segment == point.segment { result[result.count-1].append(point) }
            else { result.append([point]) }
        }
        return result
    }
    public mutating func pause(at date: Date = Date()) {
        guard state == .recording else { return }
        activeSeconds = duration(at: date); intervalStartedAt = nil; state = .paused
    }
    public mutating func resume(at date: Date = Date()) {
        guard state == .paused else { return }
        state = .recording; intervalStartedAt = date; segment += 1
    }
    public mutating func finish(at date: Date = Date()) {
        if state == .recording { pause(at: date) }
        endedAt = date; state = .finished
    }
    /// Reject invalid, old, duplicate and implausible fixes. Never bridge a gap or pause.
    public mutating func ingest(_ candidate: TrackPoint, now: Date = Date()) -> TrackPoint? {
        guard state == .recording, candidate.coordinate.isValid,
              candidate.horizontalAccuracy.isFinite, (0...65).contains(candidate.horizontalAccuracy),
              now.timeIntervalSince(candidate.timestamp) <= 15, candidate.timestamp.timeIntervalSince(now) <= 2,
              candidate.timestamp >= (intervalStartedAt ?? startedAt) else { return nil }
        var point = candidate
        point.altitude = candidate.altitude.flatMap { $0.isFinite ? $0 : nil }
        point.speed = candidate.speed.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        point.course = candidate.course.flatMap { $0.isFinite && (0..<360).contains($0) ? $0 : nil }
        point.heading = candidate.heading.flatMap { $0.isFinite && (0..<360).contains($0) ? $0 : nil }
        if let previous = points.last {
            let delta = point.timestamp.timeIntervalSince(previous.timestamp)
            guard delta > 0 else { return nil }
            if previous.segment == segment {
                if delta > 15 { segment += 1 }
                else {
                    let step = previous.coordinate.distance(to: point.coordinate)
                    guard step <= 450 * delta + previous.horizontalAccuracy + point.horizontalAccuracy else { return nil }
                    // Accumulate sub-threshold walking steps from an anchor, not just the previous fix.
                    let anchor = distanceAnchor ?? previous
                    let accumulated = anchor.coordinate.distance(to: point.coordinate)
                    if accumulated >= max(3, min(anchor.horizontalAccuracy, point.horizontalAccuracy) * 0.35) {
                        distance += accumulated
                        distanceAnchor = point
                    }
                }
            }
        }
        point.segment = segment
        if points.last?.segment != segment || distanceAnchor == nil { distanceAnchor = point }
        points.append(point)
        return point
    }
}

public enum TrackExport {
    public static func gpx(_ session: TrackSession) -> String {
        let formatter = ISO8601DateFormatter()
        func xml(_ value: String) -> String {
            value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&apos;")
        }
        let segments = session.segments.map { points in
            "<trkseg>\n" + points.map { p in
                let elevation = p.altitude.map { "<ele>\($0)</ele>" } ?? ""
                return "<trkpt lat=\"\(p.coordinate.latitude)\" lon=\"\(p.coordinate.longitude)\">\(elevation)<time>\(formatter.string(from: p.timestamp))</time></trkpt>"
            }.joined(separator: "\n") + "\n</trkseg>"
        }.joined(separator: "\n")
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<gpx version=\"1.1\" creator=\"Altiscope\" xmlns=\"http://www.topografix.com/GPX/1/1\"><trk><name>\(xml(session.title))</name><desc>\(xml(session.notes))</desc>\(segments)</trk></gpx>"
    }
}
