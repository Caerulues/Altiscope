import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var preferences: MapPreferences
    @State private var maps = false
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                Text("MAKE IT YOURS").smallLabel()
                Text("旅程，由你掌控").font(.system(size:27,weight:.semibold))
                Button { maps = true } label: { HStack { Image(systemName:"square.3.layers.3d").foregroundStyle(Theme.accent); VStack(alignment:.leading,spacing:6) { Text("地图与图层").font(.system(size:16,weight:.medium)); Text(preferences.provider.title).font(.system(size:12)).foregroundStyle(Theme.secondary) }; Spacer(); Image(systemName:"chevron.right") }.panel() }.buttonStyle(.plain)
                info("iphone","存储在这台 iPhone","无需注册。轨迹与运动数据保存在本机；使用系统分享菜单时才导出文件。卸载应用会删除本地记录，请提前导出。")
                info("wifi.slash","离线也能记录","GPS、指南针和加速度采集不依赖地图加载。离线轨迹画布随时可用；在线底图需要网络或地图提供方允许的离线数据。")
                info("moon","锁屏与后台","开始记录后启用后台定位并显示系统定位指示。暂停或结束会停止传感器。系统强制终止、用户划掉应用或设备重启后，需重新打开并继续记录。后台运动采样可能被系统限制。")
                info("location","精度与方向","原始定位与导出采用 WGS 84。高德显示时通过官方转换接口适配坐标。手机朝向来自指南针，移动方向来自 GPS，两者不一定相同。")
                VStack(alignment:.leading,spacing:10) {
                    Text("Antiscope 1.0").font(.system(size:15,weight:.medium))
                    Text("设计参考 Volanta 的地图中心布局、紫色航迹、详情标签与日志结构。Antiscope 为独立作品，与 Orbx / Volanta 无隶属关系。").font(.system(size:11)).foregroundStyle(Theme.secondary)
                    Link("Volanta 官方功能介绍",destination:URL(string:"https://volanta.app/features/")!).font(.system(size:12))
                    #if canImport(GoogleMaps)
                    GoogleLegalView()
                    #endif
                }.panel()
            }.padding(20)
        }.sheet(isPresented:$maps) { MapSettingsView() }.scrollIndicators(.hidden)
    }
    private func info(_ icon:String,_ title:String,_ text:String) -> some View {
        VStack(alignment:.leading,spacing:12) { Label(title,systemImage:icon).font(.system(size:15,weight:.medium)).foregroundStyle(Theme.accent); Text(text).font(.system(size:12)).foregroundStyle(Theme.secondary).fixedSize(horizontal:false,vertical:true) }.frame(maxWidth:.infinity,alignment:.leading).panel()
    }
}
struct MapSettingsView: View {
    @EnvironmentObject var preferences: MapPreferences
    @Environment(\.dismiss) private var dismiss
    @State private var pending: MapProvider?
    @State private var offlineManager = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    Text("选择你的视角").font(.system(size:27,weight:.semibold))
                    Text("切换底图不会中断记录，也不会改变原始定位数据。").font(.system(size:12)).foregroundStyle(Theme.secondary)
                    ForEach(MapProvider.allCases) { provider in
                        Button {
                            if provider == .google && !preferences.consentGoogle || provider == .amap && !preferences.consentAMap { pending = provider }
                            else { preferences.provider = provider }
                        } label: {
                            HStack(spacing:14) {
                                Image(systemName:provider.symbol).font(.system(size:23)).foregroundStyle(Theme.accent).frame(width:32)
                                VStack(alignment:.leading,spacing:7) { Text(provider.title).font(.system(size:15,weight:.medium)); Text(provider.subtitle).font(.system(size:10)).foregroundStyle(Theme.secondary) }
                                Spacer(); Image(systemName:preferences.provider == provider ? "checkmark.circle.fill" : "circle").foregroundStyle(preferences.provider == provider ? Theme.accent : Theme.secondary)
                            }.panel()
                        }.buttonStyle(.plain)
                    }
                    Text(preferences.availability).font(.system(size:11)).foregroundStyle(Theme.accent)
                    if preferences.provider != .offline && preferences.providerReady { Toggle("卫星底图",isOn:$preferences.satellite).font(.system(size:14)).panel() }
                    VStack(alignment:.leading,spacing:12) {
                        Text("离线使用").font(.system(size:15,weight:.semibold))
                        Text("离线轨迹不含街道底图。Google 地图不提供本应用可下载的离线区域。高德离线地图需要对应服务权限并预先下载数据，11.0 及以上 SDK 需向高德开通高阶服务。").font(.system(size:12)).foregroundStyle(Theme.secondary)
                        #if canImport(MAMapKit) && !targetEnvironment(simulator)
                        if preferences.amapReady { Button("高德离线地图管理") { offlineManager = true } }
                        #endif
                        Link("高德离线服务说明",destination:URL(string:"https://lbs.amap.com/api/ios-sdk/guide/create-map/use-offlinemap")!).font(.system(size:12))
                    }.panel()
                    if !preferences.providerReady { Text("此地图暂未就绪，已回退到离线画布。开发者需配置对应 iOS SDK Key；不会用其他来源的底图冒充。 ").font(.system(size:11)).foregroundStyle(Theme.secondary) }
                }.padding(20)
            }.background(Theme.background).navigationTitle("地图来源").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("完成") { dismiss() } } }
                .sheet(item:$pending) { provider in consent(provider) }
                #if canImport(MAMapKit) && !targetEnvironment(simulator)
                .sheet(isPresented:$offlineManager) { AMapOfflineManager() }
                #endif
        }.preferredColorScheme(.dark)
    }
    private func consent(_ provider:MapProvider) -> some View {
        VStack(alignment:.leading,spacing:22) {
            Text("使用 \(provider.title)").font(.system(size:25,weight:.semibold))
            Text("启用后，地图 SDK 会连接其提供方服务器加载当前可视区域，并按其隐私政策处理网络、设备及地图使用信息。Antiscope 不上传你的完整轨迹日志；地图视口会反映你正在查看的位置。").font(.system(size:15)).foregroundStyle(Theme.secondary)
            Link("阅读提供方隐私政策",destination:URL(string:provider == .google ? "https://policies.google.com/privacy" : "https://lbs.amap.com/pages/privacy/")!)
            Link("阅读服务条款",destination:URL(string:provider == .google ? "https://cloud.google.com/maps-platform/terms" : "https://lbs.amap.com/pages/terms/")!)
            Button { if provider == .google { preferences.consentGoogle = true } else { preferences.consentAMap = true }; preferences.provider = provider; pending = nil } label: { Text("同意并启用地图").frame(maxWidth:.infinity).padding(16) }.buttonStyle(PrimaryButton())
            Button("继续使用离线轨迹") { pending = nil }.frame(maxWidth:.infinity)
        }.padding(25).presentationDetents([.medium,.large])
    }
}
