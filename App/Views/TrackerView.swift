import SwiftUI
import Charts

struct TrackerView: View {
    @EnvironmentObject var recorder: Recorder
    @EnvironmentObject var preferences: MapPreferences
    @Binding var layers: Bool
    @State private var resetToken = 0
    @State private var follow = true
    @State private var detailTab = 0
    @State private var confirmFinish = false
    @State private var editingNotes = false
    var session: TrackSession? { recorder.displayed }
    var viewing: Bool { recorder.selected != nil }
    var sample: TrackPoint? {
        if viewing { return session?.points.last }
        guard recorder.isRecording, recorder.hasFreshFix, let point = recorder.active?.points.last,
              recorder.now.timeIntervalSince(point.timestamp) < 15 else { return nil }
        return point
    }
    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width > 700 {
                HStack(spacing:0) { detailPanel.frame(width:360); map }
            } else {
                VStack(spacing:0) { map.frame(height:max(210,geometry.size.height * 0.40)); detailPanel }
            }
        }
        .confirmationDialog("结束并保存这段轨迹？",isPresented:$confirmFinish,titleVisibility:.visible) { Button("结束并保存") { recorder.finish() }; Button("继续记录",role:.cancel) {} }
        .sheet(isPresented:$editingNotes) { NotesView() }
    }
    private var detailPanel: some View {
        VStack(spacing:0) {
            ScrollView { details }.scrollIndicators(.hidden)
            controls.padding(.horizontal,20).padding(.top,10).padding(.bottom,14)
        }.background(Theme.panel)
    }
    private var map: some View {
        RouteMapView(resetToken:resetToken,follow:follow && !viewing)
            .overlay(alignment:.topLeading) {
                VStack(alignment:.leading,spacing:7) {
                    Text(session?.isDemo == true ? "DEMO ROUTE" : viewing ? "ROUTE REPLAY" : "LIVE TRACKING").smallLabel()
                    Text(session?.isDemo == true ? "示例轨迹 · 非实测" : viewing ? "已保存的旅程" : recorder.isRecording ? recorder.hasFreshFix ? "GPS 已连接" : "等待 GPS 信号" : recorder.active?.state == .paused ? "记录已暂停" : "准备出发").font(.system(size:12,weight:.medium))
                }.padding(12).background(Theme.background.opacity(0.88),in:RoundedRectangle(cornerRadius:12)).padding(14)
            }
            .overlay(alignment:.topTrailing) {
                VStack(spacing:8) {
                    RoundButton(symbol:"square.3.layers.3d",label:"切换地图来源") { layers = true }
                    RoundButton(symbol:"arrow.up.left.and.arrow.down.right",label:"适配整条轨迹") { resetToken += 1 }
                    if recorder.isRecording && !viewing { RoundButton(symbol:follow ? "location.fill" : "location",label:follow ? "暂停跟随" : "跟随当前位置",active:follow) { follow.toggle() } }
                    if preferences.provider != .offline && preferences.providerReady { RoundButton(symbol:preferences.perspective ? "view.2d" : "view.3d",label:"切换地图倾斜",active:preferences.perspective) { preferences.perspective.toggle() } }
                }.padding(14)
            }
            .overlay(alignment:.bottomTrailing) { Text("N ↑").font(.system(size:11,weight:.semibold,design:.monospaced)).foregroundStyle(Theme.secondary).padding(12).background(Theme.background.opacity(0.8),in:Capsule()).padding(12) }
    }
    private var details: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack(spacing:8) {
                Image(systemName:preferences.provider.symbol).foregroundStyle(Theme.accent)
                Text(preferences.availability).font(.system(size:9,weight:.medium,design:.monospaced)).foregroundStyle(Theme.secondary).lineLimit(2)
                Spacer(); if !recorder.isOnline { Image(systemName:"wifi.slash").foregroundStyle(Theme.secondary) }
            }.padding(.top,14)
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:5) {
                    Text(session?.title ?? "下一段旅程").font(.system(size:22,weight:.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(session.map { "\($0.mode.title)  /  \($0.startedAt.formatted(date:.abbreviated,time:.shortened))" } ?? "iPhone GPS · 指南针 · 加速度计").font(.system(size:10)).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength:8)
                if session != nil {
                    Menu {
                        Button("导出 GPX",systemImage:"point.topleft.down.to.point.bottomright.curvepath") { recorder.export(gpx:true) }
                        Button("导出完整 JSON",systemImage:"doc.text") { recorder.export(gpx:false) }
                        if session?.isDemo == false { Button("名称与笔记",systemImage:"square.and.pencil") { editingNotes = true } }
                    } label: { Image(systemName:"ellipsis").frame(width:40,height:40).background(Theme.elevated,in:Circle()) }.accessibilityLabel("轨迹操作")
                }
            }
            HStack(spacing:0) {
                Metric(title:"距离",value:Display.distance(session?.distance ?? 0),unit:"km")
                Rectangle().fill(Theme.line).frame(width:1,height:35).padding(.horizontal,15)
                VStack(alignment:.leading,spacing:6) {
                    Text("记录时长").font(.system(size:11)).foregroundStyle(Theme.secondary)
                    Text(Display.duration(session?.duration(at:recorder.now) ?? 0)).font(.system(size:24,weight:.medium,design:.rounded)).monospacedDigit().minimumScaleFactor(0.7)
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            HStack(spacing:0) { detailButton(0,"实时数据"); detailButton(1,"统计曲线"); detailButton(2,"轨迹信息") }.overlay(alignment:.bottom) { Rectangle().fill(Theme.line).frame(height:1) }
            if detailTab == 0 {
                HStack(spacing:12) {
                    Metric(title:"地速",value:Display.number(sample?.speed.map { $0*3.6 },decimals:1),unit:"km/h")
                    Metric(title:"海拔",value:Display.number(sample?.altitude),unit:"m")
                    Metric(title:viewing ? "记录航向" : recorder.headingReference,value:Display.number(viewing ? sample?.heading : recorder.freshHeading),unit:"°")
                }
                HStack(spacing:6) {
                    Circle().fill(recorder.hasFreshFix || viewing ? Theme.mint : Theme.secondary).frame(width:5,height:5)
                    Text(viewing ? "\(session?.points.count ?? 0) 个定位点 · \(session?.segments.count ?? 0) 段轨迹" : recorder.reducedAccuracy ? "当前为模糊定位，请在系统设置中启用精确位置" : recorder.hasFreshFix ? "定位精度 ±\(Int(recorder.location?.horizontalAccuracy ?? 0)) m · 自动保存" : "有效信号到达后自动绘制轨迹").font(.system(size:10)).foregroundStyle(Theme.secondary)
                }
            } else if detailTab == 1 { RouteChart(session:session).frame(height:130) }
            else {
                VStack(alignment:.leading,spacing:8) {
                    Text(session?.notes.isEmpty == false ? session!.notes : "旅途中的想法，也值得记录。").font(.system(size:12)).foregroundStyle(Theme.secondary)
                    Text("\(session?.points.count ?? 0) GPS 点 · \(session?.motion.count ?? 0) 运动采样").font(.system(size:10,design:.monospaced)).foregroundStyle(Theme.accent)
                    if session != nil && session?.isDemo == false { Button("编辑笔记") { editingNotes = true }.font(.system(size:12)) }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
        }.padding(.horizontal,20).padding(.bottom,18).background(Theme.panel)
    }
    private func detailButton(_ index:Int,_ title:String) -> some View {
        Button { detailTab = index } label: { Text(title).font(.system(size:11,weight:.medium)).foregroundStyle(detailTab == index ? Theme.accent : Theme.secondary).frame(maxWidth:.infinity).padding(.bottom,12).overlay(alignment:.bottom) { if detailTab == index { Capsule().fill(Theme.accent).frame(height:2) } } }
    }
    private var controls: some View {
        VStack(spacing:9) {
            if viewing {
                Button { recorder.returnToLive() } label: { Label(recorder.active == nil ? "返回实时记录" : "返回当前行程",systemImage:"location.north.line.fill").frame(maxWidth:.infinity).padding(.vertical,14) }.buttonStyle(PrimaryButton())
            } else if recorder.active != nil {
                HStack(spacing:10) {
                    Button { recorder.isRecording ? recorder.pause() : recorder.start() } label: { Label(recorder.isRecording ? "暂停记录" : "继续记录",systemImage:recorder.isRecording ? "pause.fill" : "play.fill").frame(maxWidth:.infinity).padding(.vertical,14) }.buttonStyle(PrimaryButton())
                    Button { confirmFinish = true } label: { Image(systemName:"stop.fill").frame(width:52,height:48).background(Theme.elevated,in:RoundedRectangle(cornerRadius:13)) }.accessibilityLabel("结束记录")
                }
            } else {
                HStack(spacing:10) {
                    Menu { ForEach(TravelMode.allCases,id:\.self) { mode in Button(mode.title,systemImage:mode.symbol) { recorder.mode = mode } } } label: { Image(systemName:recorder.mode.symbol).frame(width:50,height:48).background(Theme.elevated,in:RoundedRectangle(cornerRadius:13)) }.accessibilityLabel("出行方式")
                    Button { recorder.start() } label: { Label("开始记录",systemImage:"record.circle").frame(maxWidth:.infinity).padding(.vertical,14) }.buttonStyle(PrimaryButton()).accessibilityIdentifier("start-recording")
                }
                Button("浏览示例轨迹") { recorder.showDemo() }.font(.system(size:11)).foregroundStyle(Theme.secondary).padding(.vertical,3)
            }
        }
    }
}
struct PrimaryButton: ButtonStyle {
    func makeBody(configuration:Configuration) -> some View { configuration.label.font(.system(size:14,weight:.semibold)).foregroundStyle(.white).background(LinearGradient(colors:[Theme.purple,Color(hex:0x6542D4)],startPoint:.leading,endPoint:.trailing),in:RoundedRectangle(cornerRadius:13)).opacity(configuration.isPressed ? 0.75 : 1) }
}
struct RouteChart: View {
    let session: TrackSession?
    @State private var speed = false
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack { Text(speed ? "地速 · km/h" : "海拔 · m").font(.system(size:10)).foregroundStyle(Theme.secondary); Spacer(); Button(speed ? "查看海拔" : "查看速度") { speed.toggle() }.font(.system(size:10)) }
            if let session, !session.points.isEmpty {
                Chart(RouteDisplay.sampled(session.points,limit:900)) { point in
                    if let value = speed ? point.speed.map({ $0*3.6 }) : point.altitude {
                        LineMark(x:.value("时间",point.timestamp),y:.value("数值",value),series:.value("轨迹段",point.segment)).foregroundStyle(Theme.accent).lineStyle(StrokeStyle(lineWidth:1.7))
                    }
                }.chartXAxis { AxisMarks(values:.automatic(desiredCount:3)) { AxisValueLabel(format:.dateTime.hour().minute()).foregroundStyle(Theme.secondary) } }
                    .chartYAxis { AxisMarks(position:.leading,values:.automatic(desiredCount:3)) { AxisGridLine().foregroundStyle(Theme.line); AxisValueLabel().foregroundStyle(Theme.secondary) } }
            } else { Text("开始记录后查看高度与速度变化").font(.system(size:12)).foregroundStyle(Theme.secondary).frame(maxWidth:.infinity,maxHeight:.infinity) }
        }
    }
}
