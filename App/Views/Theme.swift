import SwiftUI

enum Theme {
    static let background = Color(hex: 0x0C0E13)
    static let panel = Color(hex: 0x161920)
    static let elevated = Color(hex: 0x20232D)
    static let line = Color.white.opacity(0.09)
    static let secondary = Color(hex: 0x9399AC)
    static let accent = Color(hex: 0xA58AFF)
    static let purple = Color(hex: 0x7855EE)
    static let mint = Color(hex: 0x73DFC5)
}
extension Color {
    init(hex: UInt) { self.init(red: Double((hex >> 16) & 255)/255, green: Double((hex >> 8) & 255)/255, blue: Double(hex & 255)/255) }
}
extension View {
    func panel() -> some View { self.padding(18).background(Theme.panel, in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.line)) }
    func smallLabel() -> some View { self.font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.4).foregroundStyle(Theme.secondary) }
}
enum Display {
    static func number(_ value: Double?, decimals: Int = 0) -> String { value.map { String(format: "%.*f", decimals, $0) } ?? "—" }
    static func duration(_ seconds: Double) -> String {
        let value = max(0,Int(seconds)); return String(format: "%02d:%02d:%02d", value/3600, value/60%60, value%60)
    }
    static func distance(_ meters: Double) -> String { String(format: "%.2f", meters/1000) }
}
struct StatusPill: View {
    var text: String; var color: Color = Theme.mint
    var body: some View { HStack(spacing: 5) { Circle().fill(color).frame(width: 5, height: 5); Text(text).font(.system(size: 10, weight: .semibold)) }.padding(.horizontal, 9).padding(.vertical, 7).background(color.opacity(0.10), in: Capsule()).foregroundStyle(color) }
}
struct Metric: View {
    var title: String; var value: String; var unit: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11)).foregroundStyle(Theme.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 24, weight: .medium, design: .rounded)).monospacedDigit().minimumScaleFactor(0.65)
                Text(unit).font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }.lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
}
struct RoundButton: View {
    let symbol: String; let label: String; var active = false; var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 16, weight: .medium)).frame(width: 44, height: 44).foregroundStyle(active ? Theme.accent : .white).background(Theme.panel.opacity(0.95), in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.line)) }
            .accessibilityLabel(label)
    }
}
