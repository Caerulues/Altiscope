import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var recorder: Recorder
    @EnvironmentObject var preferences: MapPreferences
    @State private var maps = false
    @AppStorage("chartUnits") private var unitName = DisplayUnits.metric.rawValue
    private var units: DisplayUnits { DisplayUnits(rawValue: unitName) ?? .metric }
    @AppStorage("experimentalInertialNavigation") private var experimental = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("MAKE IT YOURS").smallLabel()
                Text("旅程，由你掌控").font(.title2.bold())
                Button { maps = true } label: { Label("地图与图层 · \(preferences.provider.title)", systemImage: "square.3.layers.3d").frame(maxWidth: .infinity, alignment: .leading).panel() }.buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 12) {
                    Text("统计与高度单位").font(.headline)
                    Text(units == .metric ? "公制 · 海拔 m，地速 km/h" : "航空 · 海拔 ft，地速 kts")
                        .font(.subheadline).foregroundStyle(Theme.secondary)
                    Button(units.switchTitle) {
                        unitName = units == .metric ? DisplayUnits.aviation.rawValue : DisplayUnits.metric.rawValue
                    }.buttonStyle(.bordered)
                    Text("用于统计曲线和地图点选海拔，自动保存你的选择。")
                        .font(.footnote).foregroundStyle(Theme.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).panel()
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("实验惯性预测", isOn: $experimental).disabled(recorder.active != nil)
                    Text("默认关闭，下一段旅程生效。开启后以运动采样连续预测，并约每 5 秒检查新定位观测。虚线为估计轨迹；超出短时预测限制时保留缺口。尚未经真机标定，不承诺精度或后台连续性。").font(.footnote).foregroundStyle(Theme.secondary)
                }.panel()
                info("存储与隐私", "轨迹与原始运动采样保存在本机；主动导出时生成文件。卸载应用会删除本地记录。Apple 地图会连接系统地图服务；离线画布不加载街道底图。")
                info("坐标与高度", "原始记录和 MapKit 输入均使用 WGS 84。轨迹按海拔采用本项目自定颜色：低空黄、绿、青、蓝紫、高空紫；灰色表示高度未知，不以零海拔推定地面。")
                info("后台记录", "锁屏时由系统调度定位和运动更新。运动回调中断后不跨间隔积分；用户暂停或强制终止后需主动继续。")
                info("Altiscope 1.0", "独立作品，界面设计参考 Volanta，与 Orbx / Volanta 无隶属关系。不能用于测绘或航空导航。")
            }.padding(20)
        }.sheet(isPresented: $maps) { MapSettingsView() }
    }
    private func info(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) { Text(title).font(.headline); Text(text).font(.footnote).foregroundStyle(Theme.secondary) }.frame(maxWidth: .infinity, alignment: .leading).panel()
    }
}
struct MapSettingsView: View {
    @EnvironmentObject var preferences: MapPreferences
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("地图来源") {
                    ForEach(MapProvider.allCases) { provider in
                        Button { preferences.provider = provider } label: {
                            HStack { Label(provider.title, systemImage: provider.symbol); Spacer(); if preferences.provider == provider { Image(systemName: "checkmark") } }
                        }
                    }
                }
                if preferences.provider == .apple { Toggle("卫星底图", isOn: $preferences.satellite) }
                Section { Text("切换底图不改变记录。离线画布显示轨迹和当前位置，不含街道底图。").font(.footnote) }
            }.navigationTitle("地图与图层").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
}
