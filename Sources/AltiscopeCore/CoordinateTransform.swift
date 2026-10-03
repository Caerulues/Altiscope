import Foundation

// Swift port of wandergis/coordtransform 2.1.2, commit
// 606c6f3b57b6f1d60458793fea39928d2b11b637 (WGS84/GCJ02 functions only).
// Copyright (c) 2015 记忆的残骸. MIT license: App/Resources/CoordTransform-LICENSE.txt.
// Upstream argument order is (longitude, latitude); Coordinate uses (latitude, longitude).
public enum CoordTransform {
    public static let upstreamCommit = "606c6f3b57b6f1d60458793fea39928d2b11b637"
    private static let axis = 6_378_245.0
    private static let eccentricity = 0.00669342162296594323
    /// Reproduces the upstream mathematical gate, NOT a mainland boundary classifier.
    public static func outsideUpstreamRectangle(_ coordinate: Coordinate) -> Bool {
        !(coordinate.longitude > 73.66 && coordinate.longitude < 135.05 && coordinate.latitude > 3.86 && coordinate.latitude < 53.55)
    }
    public static func wgs84ToGCJ02(_ coordinate: Coordinate) -> Coordinate {
        guard coordinate.isValid, !outsideUpstreamRectangle(coordinate) else { return coordinate }
        let change = delta(coordinate)
        return Coordinate(coordinate.latitude + change.latitude, coordinate.longitude + change.longitude)
    }
    /// Upstream approximate inverse, intentionally not an iterative exact inverse.
    public static func gcj02ToWGS84(_ coordinate: Coordinate) -> Coordinate {
        guard coordinate.isValid, !outsideUpstreamRectangle(coordinate) else { return coordinate }
        let change = delta(coordinate)
        return Coordinate(coordinate.latitude - change.latitude, coordinate.longitude - change.longitude)
    }
    private static func delta(_ coordinate: Coordinate) -> Coordinate {
        let x = coordinate.longitude - 105, y = coordinate.latitude - 35
        let radians = coordinate.latitude / 180 * Double.pi
        let sine = sin(radians), magic = 1 - eccentricity * sine * sine, root = sqrt(magic)
        let latitude = latitudeDelta(x, y) * 180 / ((axis * (1-eccentricity)) / (magic * root) * .pi)
        let longitude = longitudeDelta(x, y) * 180 / (axis / root * cos(radians) * .pi)
        return Coordinate(latitude, longitude)
    }
    private static func latitudeDelta(_ x: Double, _ y: Double) -> Double {
        var result = -100 + 2*x + 3*y + 0.2*y*y + 0.1*x*y + 0.2*sqrt(abs(x))
        result += (20*sin(6*x * .pi) + 20*sin(2*x * .pi)) * 2/3
        result += (20*sin(y * .pi) + 40*sin(y/3 * .pi)) * 2/3
        result += (160*sin(y/12 * .pi) + 320*sin(y * .pi/30)) * 2/3
        return result
    }
    private static func longitudeDelta(_ x: Double, _ y: Double) -> Double {
        var result = 300 + x + 2*y + 0.1*x*x + 0.1*x*y + 0.1*sqrt(abs(x))
        result += (20*sin(6*x * .pi) + 20*sin(2*x * .pi)) * 2/3
        result += (20*sin(x * .pi) + 40*sin(x/3 * .pi)) * 2/3
        result += (150*sin(x/12 * .pi) + 300*sin(x/30 * .pi)) * 2/3
        return result
    }
}
public enum GeographicReference: String, Sendable { case wgs84, gcj02 }
public enum DisplayRegion: Sendable {
    case confirmedMainland, outsideMainland, unverifiedBoundary
    /// Only use verified region metadata from a trusted provider/test; do not infer it from the rectangle.
    public init(verifiedCountryCode: String?, boundaryIsUncertain: Bool) {
        guard let code = verifiedCountryCode?.uppercased(), !boundaryIsUncertain else { self = .unverifiedBoundary; return }
        self = code == "CN" ? .confirmedMainland : .outsideMainland
    }
}
public struct DisplayCoordinate: Sendable {
    public let value: Coordinate
    public let reference: GeographicReference
    public init(_ value: Coordinate, reference: GeographicReference) { self.value = value; self.reference = reference }
    public func adapted(to target: GeographicReference, region: DisplayRegion) -> DisplayCoordinate {
        guard reference != target, value.isValid, case .confirmedMainland = region, !CoordTransform.outsideUpstreamRectangle(value) else { return self }
        return DisplayCoordinate(target == .gcj02 ? CoordTransform.wgs84ToGCJ02(value) : CoordTransform.gcj02ToWGS84(value), reference: target)
    }
    /// Both Core Location and MapKit's public input contract use WGS84. Never blindly offset it.
    public static func mapKitInput(_ rawWGS84: Coordinate) -> Coordinate {
        DisplayCoordinate(rawWGS84, reference: .wgs84).adapted(to: .wgs84, region: .unverifiedBoundary).value
    }
}
