import Foundation

/// Altiscope design thresholds in physical MSL meters, not official Volanta thresholds.
public enum RouteAltitudeStyle {
    public static func colorHex(_ altitude: Double?) -> UInt {
        guard let altitude, altitude.isFinite else { return 0x9399AC }
        let feet = altitude / 0.3048
        switch feet {
        case ..<3_000: return 0xF0D85B
        case ..<10_000: return 0x75D884
        case ..<20_000: return 0x58CDEB
        case ..<30_000: return 0x7277F2
        default: return 0xAD7BF4
        }
    }
}
public enum DisplayUnits: String, CaseIterable {
    case metric, aviation
    public var altitudeLabel: String { self == .metric ? "m" : "ft" }
    public var speedLabel: String { self == .metric ? "km/h" : "kts" }
    public var switchTitle: String { self == .metric ? "切换为航空单位" : "切换为公制单位" }
    public func altitude(_ meters: Double) -> Double { self == .metric ? meters : meters / 0.3048 }
    public func speed(_ metersPerSecond: Double) -> Double { self == .metric ? metersPerSecond * 3.6 : metersPerSecond / (1852.0 / 3600) }
}
