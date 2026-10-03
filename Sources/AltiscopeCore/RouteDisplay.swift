import Foundation

/// Rendering-only reduction. Preserve breaks, missing-value boundaries and bucket extrema.
public enum RouteDisplay {
    public static func sampled(_ points: [TrackPoint], limit: Int = 1800) -> [TrackPoint] {
        guard points.count > limit, limit > 2 else { return points }
        let step = max(1, Int(ceil(Double(points.count) / Double(limit))))
        var kept = Set([0, points.count-1])
        func sameRun(_ a: TrackPoint, _ b: TrackPoint) -> Bool {
            a.segment == b.segment && a.estimated == b.estimated && (a.timestamp == nil) == (b.timestamp == nil) &&
            (a.altitude == nil) == (b.altitude == nil) && (a.speed == nil) == (b.speed == nil)
        }
        for index in points.indices {
            if index % step == 0 { kept.insert(index) }
            if index > 0, !sameRun(points[index-1], points[index]) { kept.insert(index-1); kept.insert(index) }
        }
        for start in stride(from: 0, to: points.count, by: step) {
            let indices = start..<min(start+step, points.count)
            // Keep the strongest plan-view turn in each bucket as well as height/speed extrema.
            if let first = indices.first, let last = indices.last, first != last {
                let anchor = RouteScene.mapPoint(points[first].coordinate)
                func offset(_ index: Int) -> SIMD2<Double> {
                    let value = RouteScene.mapPoint(points[index].coordinate)-anchor
                    return SIMD2(RouteScene.wrappedDelta(value.x),value.y)
                }
                let end = offset(last), length = end.x*end.x+end.y*end.y
                func deviation(_ index: Int) -> Double {
                    let p = offset(index)
                    let t = length > 0 ? min(1,max(0,(p.x*end.x+p.y*end.y)/length)) : 0
                    let delta = p-end*t
                    return delta.x*delta.x+delta.y*delta.y
                }
                if let corner = indices.max(by: { deviation($0) < deviation($1) }),
                   deviation(corner) > max(1, length * 0.0001) { kept.insert(corner) }
            }
            for value: KeyPath<TrackPoint, Double?> in [\.altitude, \.speed] {
                let valid = indices.filter { points[$0][keyPath: value] != nil }
                guard let low = valid.min(by: { points[$0][keyPath: value]! < points[$1][keyPath: value]! }),
                      let high = valid.max(by: { points[$0][keyPath: value]! < points[$1][keyPath: value]! }),
                      points[low][keyPath: value] != points[high][keyPath: value] else { continue }
                kept.insert(low); kept.insert(high)
            }
        }
        return kept.sorted().map { points[$0] }
    }
}
