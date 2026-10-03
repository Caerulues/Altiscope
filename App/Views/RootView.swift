import SwiftUI

struct RootView: View {
    @EnvironmentObject var recorder: Recorder
    @State private var tab = 0
    @State private var layers = false
    @State private var sidebarOpen = false
    @State private var hoveredDestination: Int?
    @AppStorage("clockUTC") private var clockUTC = false
    private let destinations = [("map", "轨迹"), ("square.stack.3d.up", "日志"), ("gauge.with.dots.needle.50percent", "仪表"), ("slider.horizontal.3", "设置")]
    private var iPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header(compactSidebar: iPad && geometry.size.width < 600)
                HStack(spacing: 0) {
                    if iPad && geometry.size.width >= 600 { sidebar.frame(width: 68).zIndex(10) }
                    ZStack {
                        // Keep map camera and recording-panel state across navigation changes.
                        TrackerView(layers: $layers).opacity(tab == 0 ? 1 : 0).allowsHitTesting(tab == 0).accessibilityHidden(tab != 0)
                        if tab == 1 { JournalView { tab = 0 }.background(Theme.background) }
                        if tab == 2 { InstrumentsView().background(Theme.background) }
                        if tab == 3 { SettingsView().background(Theme.background) }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if !iPad { navigation }
            }
            .overlay(alignment: .leading) {
                if iPad && geometry.size.width < 600 && sidebarOpen {
                    HStack(spacing: 0) {
                        sidebar.frame(width: 68).zIndex(10).background(Theme.background)
                        Color.black.opacity(0.25).onTapGesture { sidebarOpen = false }
                    }.padding(.top, 60)
                }
            }
        }
        .background(Theme.background).foregroundStyle(.white)
        .onChange(of: tab) { _, value in hoveredDestination = nil; if value == 0 { recorder.requestPreview() } }
        .onChange(of: sidebarOpen) { _, _ in hoveredDestination = nil }
        .sheet(isPresented: $layers) { MapSettingsView().presentationDetents([.large]).presentationDragIndicator(.visible) }
        .sheet(isPresented: Binding(get: { recorder.shareURL != nil }, set: { if !$0 { recorder.shareURL = nil } })) {
            if let url = recorder.shareURL { ShareSheet(url: url) }
        }
        .alert("Altiscope", isPresented: Binding(get: { recorder.message != nil }, set: { if !$0 { recorder.message = nil } })) {
            Button("知道了", role: .cancel) { recorder.message = nil }
            if recorder.authorization == .denied { Button("打开系统设置") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } } }
        } message: { Text(recorder.message ?? "") }
    }
    private func header(compactSidebar: Bool) -> some View {
        HStack(spacing: 10) {
            if compactSidebar { Button { sidebarOpen.toggle() } label: { Image(systemName: "sidebar.left").frame(width: 35, height: 40) }.accessibilityLabel("展开或收起导航") }
            Image("BrandIcon").resizable().frame(width: 35, height: 35).clipShape(RoundedRectangle(cornerRadius: 9))
            Text("Altiscope").font(.system(size: 20, weight: .semibold, design: .rounded))
            Spacer(minLength: 8)
            if recorder.active != nil { StatusPill(text: recorder.isRecording ? "记录中" : "已暂停", color: recorder.isRecording ? Theme.mint : Theme.accent) }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Button { clockUTC.toggle() } label: {
                    Text(clock(context.date)).font(.system(.body, design: .monospaced)).monospacedDigit().frame(minWidth: 65, minHeight: 44)
                }.accessibilityLabel(clockUTC ? "UTC 时间，点按切换当地时间" : "当地时间，点按切换 UTC")
            }
        }.padding(.horizontal, 16).padding(.vertical, 7).background(Theme.background)
    }
    private func clock(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = clockUTC ? TimeZone(secondsFromGMT: 0) : .autoupdatingCurrent
        formatter.dateFormat = "HH:mm"; return formatter.string(from: date) + (clockUTC ? "Z" : "L")
    }
    private var sidebar: some View {
        VStack(spacing: 8) {
            ForEach(destinations.indices, id: \.self) { index in
                Button { tab = index; hoveredDestination = nil; sidebarOpen = false } label: {
                    Image(systemName: destinations[index].0).font(.system(size: 21))
                        .frame(maxWidth: .infinity).frame(height: 52).contentShape(Rectangle())
                        .background(tab == index ? Theme.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(alignment: .trailing) {
                            if tab == index { Capsule().fill(Theme.accent).frame(width: 3, height: 30) }
                        }
                }
                .foregroundStyle(tab == index ? Theme.accent : Theme.secondary)
                .accessibilityLabel(destinations[index].1)
                .accessibilityAddTraits(tab == index ? .isSelected : [])
                .accessibilityIdentifier("tab-\(index)")
                .onHover { inside in hoveredDestination = inside ? index : (hoveredDestination == index ? nil : hoveredDestination) }
                .overlay(alignment: .trailing) {
                    if hoveredDestination == index {
                        HStack(spacing: 0) {
                            TooltipPointer().fill(Theme.elevated).frame(width: 7, height: 12)
                            Text(destinations[index].1).font(.callout).foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 8))
                        }.fixedSize().frame(width: 84).offset(x: 92).allowsHitTesting(false).accessibilityHidden(true)
                    }
                }.zIndex(hoveredDestination == index ? 1 : 0)
            }
            Spacer()
        }.padding(.horizontal, 8).padding(.top, 12)
    }
    private var navigation: some View {
        HStack(spacing: 0) {
            ForEach(destinations.indices, id: \.self) { index in
                Button { tab = index } label: {
                    VStack(spacing: 5) { Image(systemName: destinations[index].0).font(.system(size: 20)); Text(destinations[index].1).font(.caption2) }
                        .frame(maxWidth: .infinity).frame(minHeight: 49).foregroundStyle(tab == index ? Theme.accent : Theme.secondary)
                }.accessibilityIdentifier("tab-\(index)")
            }
        }.background(Theme.background).overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct TooltipPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(); path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); path.closeSubpath(); return path
    }
}
