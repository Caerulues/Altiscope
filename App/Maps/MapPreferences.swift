import SwiftUI

enum MapProvider: String, CaseIterable, Identifiable {
    case apple, offline
    var id: String { rawValue }
    var title: String { self == .apple ? "Apple 地图" : "离线轨迹" }
    var subtitle: String { self == .apple ? "系统地图" : "无需网络 · 仅轨迹与经纬网" }
    var symbol: String { self == .apple ? "map" : "point.topleft.down.to.point.bottomright.curvepath" }
}
@MainActor final class MapPreferences: ObservableObject {
    @Published var provider: MapProvider { didSet { UserDefaults.standard.set(provider.rawValue, forKey: "mapProvider") } }
    @Published var satellite = false
    @Published var perspective = false
    let heightScale = 1.0
    init() {
        provider = MapProvider(rawValue: UserDefaults.standard.string(forKey: "mapProvider") ?? "") ?? .apple
        UserDefaults.standard.set(provider.rawValue, forKey: "mapProvider")
        UserDefaults.standard.removeObject(forKey: "consentGoogle"); UserDefaults.standard.removeObject(forKey: "consentAMap")
    }
    var providerReady: Bool { true }
    var availability: String { provider == .apple ? "APPLE MAPS" : "离线轨迹 · 无街道底图" }
}
