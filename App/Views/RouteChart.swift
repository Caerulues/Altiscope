import SwiftUI
import Charts

struct RouteChart: View {
    let session: TrackSession?
    @AppStorage("chartUnits") private var unitName = DisplayUnits.metric.rawValue
    @State private var selectedDate: Date?
    private var units: DisplayUnits { DisplayUnits(rawValue: unitName) ?? .metric }
    private var points: [TrackPoint] { RouteDisplay.sampled(session?.points ?? [], limit: 600) }
    private struct Reading: Identifiable {
        var id: String
        var time: Date
        var value: Double
        var series: String
        var estimated: Bool
        var altitude: Bool
    }
    private func readings() -> [Reading] {
        var result: [Reading] = [], altitudeRun = 0, speedRun = 0
        var previous: TrackPoint?
        for point in points {
            if previous?.segment != point.segment || previous?.estimated != point.estimated { altitudeRun += 1; speedRun += 1 }
            defer { previous = point }
            guard let time = point.timestamp else { altitudeRun += 1; speedRun += 1; continue }
            if let altitude = point.altitude {
                result.append(Reading(id: "a-\(point.id)", time: time, value: units.altitude(altitude), series: "a-\(altitudeRun)", estimated: point.estimated == true, altitude: true))
            } else { altitudeRun += 1 }
            if let speed = point.speed {
                result.append(Reading(id: "s-\(point.id)", time: time, value: units.speed(speed), series: "s-\(speedRun)", estimated: point.estimated == true, altitude: false))
            } else { speedRun += 1 }
        }
        return result
    }
    private func range(_ values: [Double], minimumSpan: Double) -> ClosedRange<Double> {
        let low = min(0, values.min() ?? 0), high = max(minimumSpan, values.max() ?? minimumSpan)
        return low...(high + (high-low) * 0.06)
    }
    var body: some View {
        let values = readings()
        let altitudeRange = range(values.filter(\.altitude).map(\.value), minimumSpan: units == .metric ? 10 : 30)
        let speedRange = range(values.filter { !$0.altitude }.map(\.value), minimumSpan: 1)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("海拔 · \(units.altitudeLabel)").foregroundStyle(Theme.accent)
                Spacer()
                Text("地速 · \(units.speedLabel)").foregroundStyle(.cyan)
            }.font(.caption2)
            if values.isEmpty {
                Text("暂无可计时的高度或地速数据").font(.footnote).foregroundStyle(Theme.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart {
                    ForEach(values) { reading in
                    let range = reading.altitude ? altitudeRange : speedRange
                    let y = (reading.value - range.lowerBound) / (range.upperBound - range.lowerBound)
                    if reading.altitude {
                        AreaMark(x: .value("UTC", reading.time), yStart: .value("基线", (0-range.lowerBound)/(range.upperBound-range.lowerBound)), yEnd: .value("海拔", y), series: .value("分段", reading.series))
                            .foregroundStyle(Theme.purple.opacity(0.16))
                    }
                    LineMark(x: .value("UTC", reading.time), y: .value("数值", y), series: .value("分段", reading.series))
                        .foregroundStyle(reading.altitude ? Theme.accent : .cyan)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: reading.estimated ? [4,3] : []))
                    }
                    if let selectedDate { RuleMark(x: .value("选中时间", selectedDate)).foregroundStyle(.white.opacity(0.15)) }
                }
                .chartYScale(domain: 0...1)
                .chartXSelection(value: $selectedDate)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0.0, 0.5, 1.0]) { value in
                        AxisGridLine().foregroundStyle(Theme.line)
                        AxisValueLabel { if let normalized = value.as(Double.self) { Text(label(normalized, range: altitudeRange, altitude: true)).foregroundStyle(Theme.accent) } }
                    }
                    AxisMarks(position: .trailing, values: [0.0, 0.5, 1.0]) { value in
                        AxisValueLabel { if let normalized = value.as(Double.self) { Text(label(normalized, range: speedRange, altitude: false)).foregroundStyle(.cyan) } }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { value in
                        AxisValueLabel { if let date = value.as(Date.self) { Text(utc(date)).foregroundStyle(Theme.secondary) } }
                    }
                }
                if let selectedDate, let point = points.filter({ $0.timestamp != nil }).min(by: { abs($0.timestamp!.timeIntervalSince(selectedDate)) < abs($1.timestamp!.timeIntervalSince(selectedDate)) }) {
                    Text("\(utc(point.timestamp!))  \(Display.number(point.altitude.map(units.altitude), decimals: 0)) \(units.altitudeLabel)  ·  \(Display.number(point.speed.map(units.speed), decimals: 1)) \(units.speedLabel)\(point.estimated == true ? " · 估计" : "")").font(.caption2).foregroundStyle(Theme.secondary)
                } else { Text("UTC 时间 · 虚线为估计值 · 灰色地图线为高度未知").font(.caption2).foregroundStyle(Theme.secondary) }
            }
        }
    }
    private func label(_ normalized: Double, range: ClosedRange<Double>, altitude: Bool) -> String {
        Display.number(range.lowerBound + normalized * (range.upperBound-range.lowerBound), decimals: 0)
    }
    private func utc(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "HH:mm'Z'"
        return formatter.string(from: date)
    }
}
