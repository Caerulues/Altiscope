import SwiftUI
import Charts

struct InstrumentsView: View {
    @EnvironmentObject var recorder: Recorder
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                Text("ONBOARD INSTRUMENTS").smallLabel()
                HStack { Text("感知每一次移动").font(.system(size:27,weight:.semibold)); Spacer() }
                Text("此页始终显示设备实时传感器，不显示示例数据。").font(.system(size:11)).foregroundStyle(Theme.secondary)
                VStack(spacing:14) {
                    HStack { Text("指南针").font(.system(size:15,weight:.medium)); Spacer(); Text(recorder.headingReference.uppercased()).smallLabel() }
                    CompassDial(heading:recorder.freshHeading).frame(height:220)
                    Text(recorder.freshHeading == nil ? "记录开始后读取 · 请远离磁性物体" : "手机顶部指向 · 与移动方向可能不同").font(.system(size:10)).foregroundStyle(Theme.secondary)
                }.panel()
                VStack(alignment:.leading,spacing:16) {
                    HStack { Text("加速度").font(.system(size:15,weight:.medium)); Spacer(); Text("m/s²").smallLabel() }
                    HStack {
                        Metric(title:"X 轴",value:Display.number(recorder.freshAcceleration?.x,decimals:2),unit:"")
                        Metric(title:"Y 轴",value:Display.number(recorder.freshAcceleration?.y,decimals:2),unit:"")
                        Metric(title:"Z 轴",value:Display.number(recorder.freshAcceleration?.z,decimals:2),unit:"")
                    }
                    let samples = Array((recorder.active?.motion ?? []).suffix(90))
                    if !samples.isEmpty {
                        Chart(Array(samples.enumerated()),id:\.offset) { item in LineMark(x:.value("时间",item.element.timestamp),y:.value("加速度",item.element.magnitude)).foregroundStyle(Theme.mint) }.chartXAxis(.hidden).chartYAxis(.hidden).frame(height:70)
                    }
                    Text(recorder.sensorMessage).font(.system(size:11)).foregroundStyle(Theme.mint)
                    Text("这里显示设备轴去重力加速度。实验惯导另用姿态转换为东、北、天坐标；估计轨迹以虚线表示，失效后保留缺口。").font(.system(size:11)).foregroundStyle(Theme.secondary).fixedSize(horizontal:false,vertical:true)
                }.panel()
                VStack(alignment:.leading,spacing:12) {
                    Text("定位质量").font(.system(size:15,weight:.medium))
                    HStack { Metric(title:"水平精度",value:Display.number(recorder.hasFreshFix ? recorder.location?.horizontalAccuracy : nil),unit:"m"); Metric(title:"移动方向",value:Display.number(recorder.hasFreshFix && (recorder.location?.course ?? -1) >= 0 ? recorder.location?.course : nil),unit:"°") }
                    Text(recorder.reducedAccuracy ? "系统当前仅提供模糊位置。" : "室内、隧道和机舱内可能无法获得有效 GPS 信号。").font(.system(size:11)).foregroundStyle(Theme.secondary)
                }.panel()
            }.padding(20)
        }.scrollIndicators(.hidden)
    }
}
struct CompassDial: View {
    var heading: Double?
    var body: some View {
        ZStack {
            Canvas { context,size in
                let center = CGPoint(x:size.width/2,y:size.height/2), radius = min(size.width,size.height)/2-18
                for i in 0..<72 {
                    let angle = Double(i)*5 * .pi/180
                    let length = i % 6 == 0 ? 12.0 : 5.0
                    var path = Path(); path.move(to:CGPoint(x:center.x+sin(angle)*(radius-length),y:center.y-cos(angle)*(radius-length))); path.addLine(to:CGPoint(x:center.x+sin(angle)*radius,y:center.y-cos(angle)*radius))
                    context.stroke(path,with:.color(i % 6 == 0 ? Theme.secondary : Theme.secondary.opacity(0.25)),lineWidth:1)
                }
                for (index,text) in ["N","E","S","W"].enumerated() {
                    let angle = Double(index)*Double.pi/2
                    context.draw(Text(text).font(.system(size:11,weight:.medium,design:.monospaced)).foregroundColor(index == 0 ? Theme.accent : Theme.secondary),at:CGPoint(x:center.x+sin(angle)*(radius-27),y:center.y-cos(angle)*(radius-27)))
                }
            }.rotationEffect(.degrees(-(heading ?? 0)))
            VStack(spacing:6) { Image(systemName:"triangle.fill").font(.system(size:11)).foregroundStyle(Theme.accent); Text(Display.number(heading)+"°").font(.system(size:39,weight:.light,design:.rounded)).monospacedDigit(); Text(heading == nil ? "WAITING" : "HEADING").smallLabel() }
        }.accessibilityElement(children:.ignore).accessibilityLabel("指南针 \(Display.number(heading)) 度")
    }
}
