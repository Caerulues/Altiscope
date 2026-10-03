import Foundation

/// Display geometry only. X/Y are east/south in a local Mercator frame; Z is MSL meters.
/// The map plane is always Z=0, including for negative elevations and nonzero starting altitude.
public struct RouteScene: Sendable {
    public static let heightScale = 1.0
    public struct Vertex: Sendable {
        public var position: SIMD3<Double>
        public var point: TrackPoint
    }
    public struct Edge: Sendable {
        public var a: Vertex
        public var b: Vertex
        public var estimated: Bool { a.point.estimated == true || b.point.estimated == true }
    }
    public let altitudeScale: Double
    public let anchor: Coordinate
    public let metersPerMapPoint: Double
    public let vertices: [Vertex]
    public let edges: [Edge]
    public let hasKnownReference: Bool
    public var maximumHeight: Double { max(0, vertices.map { $0.position.z }.max() ?? 0) }
    public var minimumHeight: Double { min(0, vertices.map { $0.position.z }.min() ?? 0) }
    public static let worldWidth = 268_435_456.0

    public init(points: [TrackPoint], altitudeReference: String?, heightScale: Double = RouteScene.heightScale) {
        altitudeScale = heightScale.isFinite && (1...20).contains(heightScale) ? heightScale : Self.heightScale
        anchor = points.first?.coordinate ?? Coordinate(0, 0)
        metersPerMapPoint = cos(anchor.latitude * .pi / 180) * 2 * .pi * 6_378_137 / Self.worldWidth
        // Legacy Altiscope observations/Demo use MSL; generic GPX explicitly carries "unknown".
        hasKnownReference = altitudeReference == nil || altitudeReference == "MSL"
        var built: [Vertex] = [], links: [Edge] = [], previous: Vertex?
        let origin = Self.mapPoint(anchor)
        for point in points {
            guard hasKnownReference, point.coordinate.isValid, abs(point.coordinate.latitude) < 85,
                  let altitude = point.altitude, altitude.isFinite else { previous = nil; continue }
            let map = Self.mapPoint(point.coordinate)
            let position = SIMD3(Self.wrappedDelta(map.x - origin.x) * metersPerMapPoint,
                                 (map.y - origin.y) * metersPerMapPoint, altitude * altitudeScale)
            let vertex = Vertex(position: position, point: point)
            if let previous, previous.point.segment == point.segment {
                // Split at the zero crossing; a single twisted quad would overlap itself.
                if previous.position.z * position.z < 0 {
                    let fraction = -previous.position.z / (position.z - previous.position.z)
                    var middle = previous
                    middle.position = previous.position + (position - previous.position) * fraction
                    middle.position.z = 0
                    links.append(Edge(a: previous, b: middle)); links.append(Edge(a: middle, b: vertex))
                } else { links.append(Edge(a: previous, b: vertex)) }
            }
            built.append(vertex); previous = vertex
        }
        vertices = built; edges = links
    }
    public static func mapPoint(_ coordinate: Coordinate) -> SIMD2<Double> {
        let latitude = min(85.05112878, max(-85.05112878, coordinate.latitude)) * .pi / 180
        return SIMD2((coordinate.longitude + 180) / 360 * worldWidth,
                     (1 - log(tan(.pi / 4 + latitude / 2)) / .pi) / 2 * worldWidth)
    }
    public static func wrappedDelta(_ delta: Double) -> Double {
        delta - (delta / worldWidth).rounded() * worldWidth
    }
}

/// A metric pinhole projection calibrated from four MapKit ground correspondences.
/// It projects real XYZ vertices; height changes homogeneous depth, not a screen-space offset.
/// Invalid/non-perspective map projections fail closed so the caller can show its 2D overlays.
public struct RouteProjection: Sendable {
    public let u: SIMD4<Double>
    public let v: SIMD4<Double>
    public let w: SIMD4<Double>
    public let viewport: SIMD2<Double>
    public func homogeneous(_ point: SIMD3<Double>) -> SIMD3<Double> {
        let p = SIMD4(point.x, point.y, point.z, 1)
        func dot(_ a: SIMD4<Double>) -> Double { a.x*p.x + a.y*p.y + a.z*p.z + a.w }
        return SIMD3(dot(u), dot(v), dot(w))
    }
    public func screen(_ point: SIMD3<Double>) -> SIMD2<Double>? {
        let p = homogeneous(point)
        guard p.x.isFinite, p.y.isFinite, p.z.isFinite, p.z > 0.001 else { return nil }
        return SIMD2(p.x / p.z, p.y / p.z)
    }
    public static func calibrate(ground: [SIMD2<Double>], screen: [SIMD2<Double>],
                                 viewport: SIMD2<Double>, cameraAltitude: Double) -> RouteProjection? {
        guard ground.count == 4, screen.count == 4, viewport.x > 0, viewport.y > 0,
              cameraAltitude.isFinite, cameraAltitude > 0 else { return nil }
        // Normalize the input before solving to remain stable at both street and flight scale.
        let scale = ground.flatMap { [abs($0.x), abs($0.y)] }.max() ?? 0
        guard scale > 0 else { return nil }
        var system: [[Double]] = []
        for (g, s) in zip(ground, screen) {
            let x = g.x / scale, y = g.y / scale
            guard x.isFinite, y.isFinite, s.x.isFinite, s.y.isFinite else { return nil }
            system.append([x,y,1,0,0,0,-s.x*x,-s.x*y,s.x])
            system.append([0,0,0,x,y,1,-s.y*x,-s.y*y,s.y])
        }
        for column in 0..<8 {
            let pivot = (column..<8).max { abs(system[$0][column]) < abs(system[$1][column]) }!
            guard abs(system[pivot][column]) > 1e-10 else { return nil }
            system.swapAt(column, pivot)
            let divisor = system[column][column]
            for j in column...8 { system[column][j] /= divisor }
            for row in 0..<8 where row != column {
                let factor = system[row][column]
                for j in column...8 { system[row][j] -= factor * system[column][j] }
            }
        }
        let h = system.map { $0[8] }
        let x = SIMD3(h[0]/scale, h[3]/scale, h[6]/scale)
        let y = SIMD3(h[1]/scale, h[4]/scale, h[7]/scale)
        let cx = viewport.x / 2, cy = viewport.y / 2
        let a = SIMD2(x.x-cx*x.z, x.y-cy*x.z), b = SIMD2(y.x-cx*y.z, y.y-cy*y.z)
        let orthogonalDenominator = x.z*y.z
        let normDenominator = x.z*x.z-y.z*y.z
        let focalSquared: Double
        if max(abs(orthogonalDenominator), abs(normDenominator)) < 1e-18 {
            // At nadir the plane alone cannot determine focal length; public camera altitude does.
            focalSquared = (a.x*a.x+a.y*a.y) * cameraAltitude * cameraAltitude
        } else if abs(orthogonalDenominator) > abs(normDenominator) {
            focalSquared = -(a.x*b.x+a.y*b.y) / orthogonalDenominator
        } else {
            focalSquared = (b.x*b.x+b.y*b.y-a.x*a.x-a.y*a.y) / normDenominator
        }
        guard focalSquared.isFinite, focalSquared > 0 else { return nil }
        let focal = sqrt(focalSquared)
        let r1 = SIMD3(a.x/focal, a.y/focal, x.z), r2 = SIMD3(b.x/focal, b.y/focal, y.z)
        func dot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double { a.x*b.x+a.y*b.y+a.z*b.z }
        let length1 = sqrt(dot(r1,r1)), length2 = sqrt(dot(r2,r2)), length = (length1+length2)/2
        guard length.isFinite, length > 0,
              abs(length1-length2)/length < 0.03,
              abs(dot(r1,r2))/(length1*length2) < 0.03 else { return nil }
        let normal = -SIMD3(r1.y*r2.z-r1.z*r2.y, r1.z*r2.x-r1.x*r2.z, r1.x*r2.y-r1.y*r2.x) / length
        // East/south axes point into the ground; negate their cross product for positive altitude.
        let z = SIMD3(focal*normal.x+cx*normal.z, focal*normal.y+cy*normal.z, normal.z)
        guard z.z < 0 else { return nil }
        return RouteProjection(u: SIMD4(x.x,y.x,z.x,h[2]), v: SIMD4(x.y,y.y,z.y,h[5]),
                               w: SIMD4(x.z,y.z,z.z,1), viewport: viewport)
    }
}

/// Fits the projected main line AND its ground footprint into the unobscured map area.
/// A translation alone must not zoom out; an under-filled overview must be allowed to zoom in.
public enum RouteViewportFit {
    public struct Adjustment: Sendable {
        public let centerOffset: SIMD2<Double>
        public let scale: Double
    }
    public static func adjustment(points: [SIMD2<Double>], minimum: SIMD2<Double>,
                                  maximum: SIMD2<Double>) -> Adjustment? {
        guard !points.isEmpty, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              minimum.x.isFinite, minimum.y.isFinite, maximum.x.isFinite, maximum.y.isFinite,
              maximum.x > minimum.x, maximum.y > minimum.y else { return nil }
        let low = SIMD2(points.map(\.x).min()!, points.map(\.y).min()!)
        let high = SIMD2(points.map(\.x).max()!, points.map(\.y).max()!)
        let extent = high - low, available = maximum - minimum
        let offset = (low + high - minimum - maximum) / 2
        let ratio = max(extent.x / available.x, extent.y / available.y)
        let contained = low.x >= minimum.x && low.y >= minimum.y && high.x <= maximum.x && high.y <= maximum.y
        // Leave breathing room, while avoiding zoom oscillation at the target boundary.
        if contained && (ratio >= 0.85 || max(extent.x, extent.y) < 1) { return nil }
        let scale: Double
        if max(extent.x, extent.y) < 1 { scale = 1 }
        else if (0.85...1).contains(ratio) { scale = 1 }
        else { scale = min(2, max(0.5, ratio / 0.92)) }
        return Adjustment(centerOffset: offset, scale: scale)
    }
}
