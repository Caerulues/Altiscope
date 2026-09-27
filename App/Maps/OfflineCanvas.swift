import SwiftUI

/// A geographic plotting surface, not an invented street map. No network or map SDK is used.
struct OfflineCanvas: View {
    var points: [TrackPoint]
    var heading: Double?
    var resetToken: Int
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @GestureState private var gestureZoom: CGFloat = 1
    @GestureState private var gesturePan: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let projection = CanvasProjection(points: points, size: geometry.size)
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0x10151C)))
                var grid = Path()
                for x in stride(from: 0.0, through: size.width, by: 32) { grid.move(to: CGPoint(x:x,y:0)); grid.addLine(to: CGPoint(x:x,y:size.height)) }
                for y in stride(from: 0.0, through: size.height, by: 32) { grid.move(to: CGPoint(x:0,y:y)); grid.addLine(to: CGPoint(x:size.width,y:y)) }
                context.stroke(grid, with: .color(.white.opacity(0.035)), lineWidth: 0.6)
                let center = CGPoint(x: size.width/2, y: size.height/2)
                for radius in [60.0, 120, 180, 240] {
                    let ring = Path(ellipseIn: CGRect(x: center.x-radius, y: center.y-radius, width: radius*2, height: radius*2))
                    context.stroke(ring, with: .color(.white.opacity(0.045)), style: StrokeStyle(lineWidth: 1, dash: [3,5]))
                }
                func position(_ coordinate: Coordinate) -> CGPoint {
                    let p = projection.project(coordinate)
                    let scale = zoom * gestureZoom
                    return CGPoint(x: (p.x-center.x)*scale+center.x+pan.width+gesturePan.width,
                                   y: (p.y-center.y)*scale+center.y+pan.height+gesturePan.height)
                }
                var path = Path()
                var segment: Int?
                for point in points {
                    let p = position(point.coordinate)
                    if segment != point.segment { path.move(to: p) } else { path.addLine(to: p) }
                    segment = point.segment
                }
                context.stroke(path, with: .color(Theme.purple.opacity(0.16)), style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round))
                context.stroke(path, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                if let first = points.first {
                    let p = position(first.coordinate)
                    context.fill(Path(ellipseIn: CGRect(x: p.x-5,y:p.y-5,width:10,height:10)), with: .color(Theme.mint))
                    context.draw(Text("起点").font(.system(size: 10,weight:.medium)).foregroundColor(Theme.mint), at: CGPoint(x:p.x,y:p.y+20))
                }
                if let last = points.last {
                    let p = position(last.coordinate)
                    context.fill(Path(ellipseIn: CGRect(x:p.x-19,y:p.y-19,width:38,height:38)), with: .color(Theme.accent.opacity(0.13)))
                    context.fill(Path(ellipseIn: CGRect(x:p.x-7,y:p.y-7,width:14,height:14)), with: .color(.white))
                    context.stroke(Path(ellipseIn: CGRect(x:p.x-7,y:p.y-7,width:14,height:14)), with: .color(Theme.accent), lineWidth: 3)
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    if let p = points.last { Text(String(format:"%.5f° %@   %.5f° %@",abs(p.coordinate.latitude),p.coordinate.latitude >= 0 ? "N" : "S",abs(p.coordinate.longitude),p.coordinate.longitude >= 0 ? "E" : "W")).font(.system(size:9,design:.monospaced)).foregroundStyle(Theme.secondary) }
                    HStack(spacing:6) { Rectangle().frame(width:40,height:2); Text("\(Int(projection.metersPerPoint * 40 / Double(zoom * gestureZoom))) m").font(.system(size:9,design:.monospaced)) }.foregroundStyle(Theme.secondary)
                }.padding(14)
            }
            .overlay {
                if points.isEmpty {
                    VStack(spacing: 15) {
                        Image(systemName:"location.north.circle").font(.system(size:48,weight:.ultraLight)).foregroundStyle(Theme.accent)
                        Text("每一段旅程，都有迹可循。").font(.system(size:15,weight:.medium))
                        Text("开始记录，轨迹会在这里延伸").font(.system(size:12)).foregroundStyle(Theme.secondary)
                    }.padding(24).background(Theme.background.opacity(0.75),in:RoundedRectangle(cornerRadius:24))
                }
            }
            .clipped()
            .gesture(MagnifyGesture().updating($gestureZoom) { v,s,_ in s = v.magnification }.onEnded { zoom = min(20,max(0.5,zoom*$0.magnification)) })
            .simultaneousGesture(DragGesture().updating($gesturePan) { v,s,_ in s = v.translation }.onEnded { pan.width += $0.translation.width; pan.height += $0.translation.height })
            .onChange(of: resetToken) { _,_ in zoom = 1; pan = .zero }
        }.accessibilityLabel("离线轨迹画布，\(points.count) 个定位点，可拖动及双指缩放")
    }
}

private struct CanvasProjection {
    var center: Coordinate
    var size: CGSize
    var metersPerPoint: Double
    init(points: [TrackPoint], size: CGSize) {
        self.size = size
        let origin = points.first?.coordinate ?? Coordinate(0,0)
        func longitudeOffset(_ lon: Double) -> Double { var d = lon-origin.longitude; if d > 180 { d -= 360 }; if d < -180 { d += 360 }; return d }
        let lats = points.map(\.coordinate.latitude)
        let lons = points.map { longitudeOffset($0.coordinate.longitude) }
        let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0, maxLon = lons.max() ?? 0
        center = Coordinate((minLat+maxLat)/2,origin.longitude+(minLon+maxLon)/2)
        let width = (maxLon-minLon) * 111_195 * max(0.01,cos(center.latitude * .pi / 180))
        let height = (maxLat-minLat) * 111_195
        metersPerPoint = max(2.5, max(width/max(100,Double(size.width)-110), height/max(100,Double(size.height)-115)))
    }
    func project(_ coordinate: Coordinate) -> CGPoint {
        var longitude = coordinate.longitude-center.longitude
        if longitude > 180 { longitude -= 360 }; if longitude < -180 { longitude += 360 }
        return CGPoint(x:size.width/2 + longitude * 111_195 * max(0.01,cos(center.latitude * .pi/180))/metersPerPoint,
                       y:size.height/2 - (coordinate.latitude-center.latitude)*111_195/metersPerPoint)
    }
}
