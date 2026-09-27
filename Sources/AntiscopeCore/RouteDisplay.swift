import Foundation

/// Reduces rendering work only. The journal and exports retain every accepted sample.
public enum RouteDisplay {
    public static func sampled(_ points: [TrackPoint], limit: Int = 1800) -> [TrackPoint] {
        guard points.count > limit, limit > 2 else { return points }
        let stride = max(1, Int(ceil(Double(points.count) / Double(limit))))
        return points.enumerated().compactMap { index, point in
            let boundary = index == 0 || index == points.count-1 ||
                points[index-1].segment != point.segment || points[index+1].segment != point.segment
            return boundary || index % stride == 0 ? point : nil
        }
    }
}
