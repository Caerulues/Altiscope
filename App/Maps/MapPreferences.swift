import SwiftUI

enum MapProvider: String, CaseIterable, Identifiable {
    case offline, amap, google, apple
    var id: String { rawValue }
    var title: String { switch self { case .offline: return "离线轨迹"; case .amap: return "高德地图"; case .google: return "Google Maps"; case .apple: return "Apple 地图" } }
    var subtitle: String { switch self {
    case .offline: return "无网络 · 无需 Key · 经纬网与轨迹"
    case .amap: return "原生 SDK · 中国大陆底图"
    case .google: return "原生 SDK · 全球底图"
    case .apple: return "系统地图 · 无需 Key"
    } }
    var symbol: String { switch self { case .offline: return "point.topleft.down.to.point.bottomright.curvepath"; case .amap: return "map.fill"; case .google: return "globe.asia.australia.fill"; case .apple: return "map" } }
}
@MainActor final class MapPreferences: ObservableObject {
    @Published var provider: MapProvider { didSet { UserDefaults.standard.set(provider.rawValue, forKey: "mapProvider") } }
    @Published var satellite = false
    @Published var perspective = false
    @Published var consentGoogle: Bool { didSet { UserDefaults.standard.set(consentGoogle, forKey: "consentGoogle") } }
    @Published var consentAMap: Bool { didSet { UserDefaults.standard.set(consentAMap, forKey: "consentAMap") } }
    init() {
        provider = MapProvider(rawValue: UserDefaults.standard.string(forKey: "mapProvider") ?? "") ?? .offline
        consentGoogle = UserDefaults.standard.bool(forKey: "consentGoogle")
        consentAMap = UserDefaults.standard.bool(forKey: "consentAMap")
    }
    nonisolated static func key(_ name: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: name) as? String,
              !value.isEmpty, !value.contains("$(") else { return nil }; return value
    }
    var googleReady: Bool {
        #if canImport(GoogleMaps)
        return Self.key("GoogleMapsAPIKey") != nil && consentGoogle
        #else
        return false
        #endif
    }
    var amapReady: Bool {
        #if canImport(MAMapKit) && !targetEnvironment(simulator)
        return Self.key("AMapAPIKey") != nil && consentAMap
        #else
        return false
        #endif
    }
    var providerReady: Bool { switch provider { case .offline, .apple: return true; case .amap: return amapReady; case .google: return googleReady } }
    var availability: String {
        switch provider {
        case .offline: return "OFFLINE CANVAS · WGS 84"
        case .apple: return "APPLE MAPS"
        case .google: return googleReady ? "GOOGLE MAPS" : "Google 未配置 · 当前显示离线轨迹"
        case .amap:
            #if targetEnvironment(simulator)
            return "高德需真机验证 · 当前显示离线轨迹"
            #else
            return amapReady ? "高德地图 · GCJ-02" : "高德未配置 · 当前显示离线轨迹"
            #endif
        }
    }
}
