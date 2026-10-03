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

#if DEBUG
extension DemoRoute {
    /// Reproducible render fixture. Never placed in the journal or enabled in Release builds.
    public static func altitudePreview() -> TrackSession {
        let start = Date(timeIntervalSince1970: 1_790_417_400)
        var route = TrackSession(title: "三维验收 · 虚构轨迹", mode: .flight, startedAt: start)
        route.isDemo = true; route.altitudeReference = "MSL"
        for index in 0...240 {
            let t = Double(index)/240, angle = t * .pi * 4
            let coordinate = Coordinate(32.076 + 0.10*sin(angle),118.792 + 0.12*cos(angle))
            let altitude: Double? = (110...114).contains(index) ? nil : index < 20 ? 0 : index > 230 ? -120 : min(12000,max(0,sin(t * .pi)*15000-1500))
            var point = TrackPoint(timestamp:start.addingTimeInterval(Double(index)*10),coordinate:coordinate,
                altitude:altitude,speed:80,segment:index<170 ? 0:1)
            point.estimated = (140...160).contains(index)
            route.points.append(point)
        }
        route.finish(at:start.addingTimeInterval(2400)); route.notes = "纯合成测试：零高度、爬升、平飞、下降、盘旋、负高度、未知高度、估计段与暂停。"
        return route
    }
}
#endif
