import SwiftUI

struct RootView: View {
    @EnvironmentObject var recorder: Recorder
    @State private var tab = 0
    @State private var layers = false
    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch tab {
                case 0: TrackerView(layers: $layers)
                case 1: JournalView { tab = 0 }
                case 2: InstrumentsView()
                default: SettingsView()
                }
            }.frame(maxWidth: .infinity,maxHeight: .infinity)
            navigation
        }.background(Theme.background).foregroundStyle(.white)
        .sheet(isPresented: $layers) { MapSettingsView().presentationDetents([.large]).presentationDragIndicator(.visible) }
        .sheet(isPresented: Binding(get: { recorder.shareURL != nil }, set: { if !$0 { recorder.shareURL = nil } })) {
            if let url = recorder.shareURL { ShareSheet(url: url).presentationDetents([.medium,.large]) }
        }
        .alert("Antiscope", isPresented: Binding(get: { recorder.message != nil },set:{ if !$0 { recorder.message = nil } })) {
            Button("知道了",role:.cancel) { recorder.message = nil }
            if recorder.authorization == .denied { Button("打开系统设置") { if let url = URL(string:UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } } }
        } message: { Text(recorder.message ?? "") }
    }
    private var header: some View {
        HStack(spacing: 10) {
            ZStack { RoundedRectangle(cornerRadius:10).fill(Theme.purple.opacity(0.18)).frame(width:35,height:35); Image(systemName:"location.north.line.fill").font(.system(size:21)).foregroundStyle(Theme.accent).rotationEffect(.degrees(25)) }
            VStack(alignment:.leading,spacing:2) { Text("Antiscope").font(.system(size:20,weight:.semibold,design:.rounded)); Text("YOUR JOURNEY, RECORDED").font(.system(size:7,weight:.medium,design:.monospaced)).tracking(1.8).foregroundStyle(Theme.secondary) }
            Spacer()
            StatusPill(text: recorder.isRecording ? "记录中" : recorder.active?.state == .paused ? "已暂停" : "本地存储",color:recorder.isRecording ? Theme.mint : Theme.accent)
        }.padding(.horizontal,20).padding(.top,8).padding(.bottom,14).background(Theme.background)
    }
    private var navigation: some View {
        HStack(spacing:0) {
            navItem(0,"map","轨迹"); navItem(1,"square.stack.3d.up","日志")
            navItem(2,"gauge.with.dots.needle.50percent","仪表"); navItem(3,"slider.horizontal.3","设置")
        }.padding(.top,13).padding(.bottom,5).background(Theme.background).overlay(alignment:.top) { Rectangle().fill(Theme.line).frame(height:1) }
    }
    private func navItem(_ index:Int,_ icon:String,_ title:String) -> some View {
        Button { tab = index } label: {
            VStack(spacing:5) { Image(systemName:icon).font(.system(size:20)); Text(title).font(.system(size:10,weight:tab == index ? .semibold : .regular)) }
                .frame(maxWidth:.infinity).foregroundStyle(tab == index ? Theme.accent : Theme.secondary)
        }.accessibilityIdentifier("tab-\(index)")
    }
}
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context:Context) -> UIActivityViewController { UIActivityViewController(activityItems:[url],applicationActivities:nil) }
    func updateUIViewController(_ uiViewController:UIActivityViewController,context:Context) {}
}
