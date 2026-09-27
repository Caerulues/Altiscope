import Foundation

public enum DemoRoute {
    /// Deliberately synthetic preview data; never persisted as a real recording.
    public static func make() -> TrackSession {
        let start = Date(timeIntervalSince1970: 1_790_417_400)
        var route = TrackSession(title: "玄武湖环线", mode: .cycling, startedAt: start)
        route.isDemo = true
        for index in 0..<241 {
            let t = Double(index) / 240
            let angle = -Double.pi * 0.65 + t * Double.pi * 1.8
            let radius = 1 + 0.10 * sin(t * 19) + 0.035 * cos(t * 57)
            let c = Coordinate(32.076 + 0.016 * sin(angle) * radius, 118.792 + 0.013 * cos(angle) * radius)
            let date = start.addingTimeInterval(Double(index) * 6)
            let p = TrackPoint(timestamp: date, coordinate: c, altitude: 18 + 7*sin(t*11) + 2*cos(t*37),
                               speed: 4.2+0.8*sin(t*17), course: (t*324+72).truncatingRemainder(dividingBy: 360), heading: 126, horizontalAccuracy: 4, verticalAccuracy: 7)
            _ = route.ingest(p, now: date)
            route.motion.append(MotionSample(timestamp: date, x: 0.12*sin(t*90), y: 0.20*cos(t*61), z: 0.06*sin(t*27)))
        }
        route.finish(at: start.addingTimeInterval(1440))
        route.notes = "示例路线由程序生成，只用于体验界面，不代表实测行程。"
        return route
    }
}
