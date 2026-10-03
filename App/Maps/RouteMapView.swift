import SwiftUI
import MapKit

private func mapCoordinate(_ raw: Coordinate) -> CLLocationCoordinate2D {
    let display = DisplayCoordinate.mapKitInput(raw)
    return CLLocationCoordinate2D(latitude: display.latitude, longitude: display.longitude)
}

struct RouteMapView: View {
    @EnvironmentObject var recorder: Recorder
    @EnvironmentObject var preferences: MapPreferences
    @AppStorage("chartUnits") private var unitName = DisplayUnits.metric.rawValue
    var resetToken: Int
    var follow: Bool
    var points: [TrackPoint] { RouteDisplay.sampled(recorder.displayed?.points ?? []) }
    var current: Coordinate? {
        guard recorder.selected == nil, let location = recorder.location,
              (0...15).contains(Date().timeIntervalSince(location.timestamp)), location.horizontalAccuracy >= 0 else { return nil }
        return Coordinate(location.coordinate.latitude, location.coordinate.longitude)
    }
    var body: some View {
        Group {
            if preferences.provider == .apple {
                AppleRouteMap(points: points, current: current, historical: recorder.selected != nil,
                    satellite: preferences.satellite, perspective: preferences.perspective, heightScale: preferences.heightScale,
                    altitudeReference: recorder.displayed?.altitudeReference, units: DisplayUnits(rawValue: unitName) ?? .metric,
                    resetToken: resetToken, follow: follow, userMoved: { recorder.followLocation = false })
            } else {
                OfflineCanvas(points: points, heading: recorder.freshHeading, resetToken: resetToken,
                    current: current, follow: follow, userMoved: { recorder.followLocation = false })
            }
        }.id("\(preferences.provider.rawValue)-\(recorder.displayed?.id.uuidString ?? "live")")
    }
}
private final class AltitudePolyline: MKPolyline {
    var color: UIColor = .gray
    var estimated = false
    var knownHeight = false
}
struct AppleRouteMap: UIViewRepresentable {
    var points: [TrackPoint]
    var current: Coordinate?
    var historical: Bool
    var satellite: Bool
    var perspective: Bool
    var heightScale: Double
    var altitudeReference: String?
    var units: DisplayUnits
    var resetToken: Int
    var follow: Bool
    var userMoved: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> RouteMapContainer {
        let host = RouteMapContainer()
        let map = host.map; map.delegate = context.coordinator
        context.coordinator.host = host
        host.renderer?.statusChanged = { [weak host, weak coordinator = context.coordinator] ready, message in
            host?.status.text = message; host?.status.isHidden = message.isEmpty
            coordinator?.refreshStyles()
        }
        host.renderer?.projectionUpdated = { [weak coordinator = context.coordinator] in coordinator?.fitHeightIfNeeded() }
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.selectPoint(_:)))
        tap.cancelsTouchesInView = false; tap.delegate = context.coordinator; map.addGestureRecognizer(tap)
        map.overrideUserInterfaceStyle = .dark; map.showsCompass = false; map.isRotateEnabled = true; map.showsBuildings = false
        map.pointOfInterestFilter = .excludingAll; map.showsUserLocation = true
        // An explicit world overview is an unknown-location state, never a fabricated fix at (0, 0).
        map.setVisibleMapRect(MKMapRect.world, animated: false)
        return host
    }
    static func dismantleUIView(_ host: RouteMapContainer, coordinator: Coordinator) {
        host.renderer?.enabled = false; host.map.delegate = nil
        host.renderer?.statusChanged = nil; host.renderer?.projectionUpdated = nil
    }
    func updateUIView(_ host: RouteMapContainer, context: Context) {
        let map = host.map
        let c = context.coordinator; c.userMoved = userMoved; c.units = units; c.points = points; c.altitudeReference = altitudeReference; c.updateReading()
        if c.satellite != satellite || c.configurationPerspective != perspective {
            let previousCamera = map.camera.copy() as! MKMapCamera
            c.satellite = satellite; c.configurationPerspective = perspective
            // Imagery's flat mode clamps pitch to zero. Non-Directions overlays keep Flyover's
            // terrain flat while retaining its pitched camera (MapKit WWDC22, 10035).
            if satellite { map.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: perspective ? .realistic : .flat) }
            else {
                let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
                configuration.pointOfInterestFilter = .excludingAll; map.preferredConfiguration = configuration
            }
            if perspective && previousCamera.pitch < 1 { previousCamera.pitch = 55 }
            map.setCamera(previousCamera, animated: false)
        }
        let scaleChanged = c.heightScale != heightScale
        if c.count != points.count || c.lastID != points.last?.id || c.historical != historical || scaleChanged {
            c.heightScale = heightScale
            c.historical = historical
            c.count = points.count; c.lastID = points.last?.id
            host.renderer?.update(points: points.map { raw in
                var display = raw; display.coordinate = DisplayCoordinate.mapKitInput(raw.coordinate); return display
            }, altitudeReference: altitudeReference, heightScale: heightScale)
            map.removeOverlays(map.overlays)
            map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })
            var run: [CLLocationCoordinate2D] = [], color: UInt?, estimated = false, knownHeight = false
            func flush() {
                guard run.count > 1 else { run = []; return }
                let line = AltitudePolyline(coordinates: run, count: run.count)
                line.color = UIColor(Color(hex: color ?? 0x9399AC)); line.estimated = estimated; line.knownHeight = knownHeight; map.addOverlay(line); run = []
            }
            for (a, b) in zip(points, points.dropFirst()) {
                guard a.segment == b.segment else { flush(); color = nil; continue }
                let known = a.altitude != nil && b.altitude != nil
                let hex = RouteAltitudeStyle.colorHex(known ? b.altitude : nil), prediction = a.estimated == true || b.estimated == true
                if hex != color || prediction != estimated || known != knownHeight { flush(); color = hex; estimated = prediction; knownHeight = known }
                if run.isEmpty { run.append(mapCoordinate(a.coordinate)) }
                run.append(mapCoordinate(b.coordinate))
            }
            flush()
            if map.overlays.isEmpty, let point = points.first {
                let coordinate = mapCoordinate(point.coordinate)
                map.addOverlay(AltitudePolyline(coordinates:[coordinate,coordinate],count:2))
            }
            for (point, title) in [(points.first, "起点"), (points.last, historical ? "终点" : "最新轨迹点")] {
                if let point { let marker = MKPointAnnotation(); marker.coordinate = mapCoordinate(point.coordinate); marker.title = title; map.addAnnotation(marker) }
            }
        }
        let requested = c.reset != resetToken
        if requested { c.reset = resetToken }
        if historical && (!c.fitted || requested) || (!follow && requested) {
            c.fitted = true
            DispatchQueue.main.async { self.fit(map); c.heightFitAttempts = perspective ? 12 : 0 }
        } else if follow, let coordinate = current ?? points.last?.coordinate,
                  requested || !c.centered || c.current != coordinate {
            c.current = coordinate
            let center = mapCoordinate(coordinate)
            if requested || !c.centered { map.setRegion(MKCoordinateRegion(center: center, latitudinalMeters: 1200, longitudinalMeters: 1200), animated: c.centered) }
            else { map.setCenter(center, animated: true) }
            c.centered = true
        }
        if c.perspective != perspective || (perspective && scaleChanged) {
            c.needsPitchedView = perspective
            c.perspective = perspective; host.renderer?.enabled = perspective
            c.selectedPoint = nil; c.updateReading()
            let camera = map.camera.copy() as! MKMapCamera; camera.pitch = perspective ? 55 : 0
            if perspective {
                let height = max(host.renderer?.scene.maximumHeight ?? 0, abs(host.renderer?.scene.minimumHeight ?? 0))
                camera.altitude = max(camera.altitude, height * 2 + 300)
                c.heightFitAttempts = (historical || !follow) && host.renderer?.detailView != true ? 12 : 0
                if host.renderer == nil { host.status.text = "2D · 此设备无法启用三维渲染"; host.status.isHidden = false }
            } else { host.status.isHidden = true }
            // Fitting against intermediate animation frames can repeatedly pull the camera back.
            map.setCamera(camera, animated: !perspective)
        }
        if perspective && follow, let height = points.last?.altitude, altitudeReference != "unknown" {
            let minimum = abs(height) * heightScale * 2 + 300
            if map.camera.altitude < minimum || (requested && map.camera.pitch < 1) {
                let camera = map.camera.copy() as! MKMapCamera; camera.altitude = max(camera.altitude, minimum)
                if requested && camera.pitch < 1 { camera.pitch = 55 }
                map.setCamera(camera, animated: false)
            }
        }
        host.renderer?.enabled = perspective
    }
    private func fit(_ map: MKMapView) {
        guard let first = points.first else { return }
        let anchor = MKMapPoint(mapCoordinate(first.coordinate))
        let world = MKMapRect.world.width
        var minX = anchor.x, maxX = anchor.x, minY = anchor.y, maxY = anchor.y
        for point in points {
            let p = MKMapPoint(mapCoordinate(point.coordinate))
            var x = p.x
            if x - anchor.x > world / 2 { x -= world }; if x - anchor.x < -world / 2 { x += world }
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let minimum = MKMapPointsPerMeterAtLatitude(first.coordinate.latitude) * 250
        var rect = MKMapRect(x: minX, y: minY, width: maxX-minX, height: maxY-minY)
        rect = rect.insetBy(dx: -max(0,(minimum-rect.width)/2), dy: -max(0,(minimum-rect.height)/2))
        // The iPad floating panel starts on the left; leave a visible corridor for the full route.
        let left: CGFloat = map.bounds.width > 700 ? min(410, map.bounds.width * 0.46) : 35
        let heading = map.camera.heading, pitch = map.camera.pitch
        map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 95, left: left, bottom: 65, right: 75), animated: false)
        if perspective {
            let camera = map.camera.copy() as! MKMapCamera
            camera.heading = heading; camera.pitch = pitch > 1 ? pitch : 55
            let height = points.compactMap(\.altitude).map { abs($0) }.max() ?? 0
            camera.altitude = max(camera.altitude, height * heightScale * 2 + 300)
            map.setCamera(camera, animated: false)
        }
    }
    class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        weak var host: RouteMapContainer?
        var satellite: Bool?
        var configurationPerspective: Bool?
        var units = DisplayUnits.metric
        var selectedPoint: TrackPoint?
        var points: [TrackPoint] = []
        var altitudeReference: String?
        var needsPitchedView = false
        var heightScale = RouteScene.heightScale
        var heightFitAttempts = 0
        var count = -1, reset = -1
        var lastID: UUID?, current: Coordinate?
        var fitted = false, centered = false, perspective = false, historical = false
        var userMoved: (() -> Void)?
        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) { detectGesture(mapView) }
        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) { detectGesture(mapView) }
        private func detectGesture(_ view: UIView) {
            func isUserGesture(_ view: UIView) -> Bool {
                (view.gestureRecognizers ?? []).contains { ($0 is UIPanGestureRecognizer || $0 is UIPinchGestureRecognizer) && [.began, .changed].contains($0.state) } || view.subviews.contains(where: isUserGesture)
            }
            if isUserGesture(view) { heightFitAttempts = 0; userMoved?() }
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let renderer = MKPolylineRenderer(overlay: overlay)
            if let line = overlay as? AltitudePolyline { renderer.strokeColor = line.color; if line.estimated { renderer.lineDashPattern = [6,4] } }
            style(renderer); renderer.lineCap = .round; return renderer
        }
        private func style(_ renderer: MKPolylineRenderer) {
            let projected = host?.renderer?.ready == true && (renderer.overlay as? AltitudePolyline)?.knownHeight == true
            renderer.alpha = projected ? 0.30 : 1; renderer.lineWidth = projected ? 1.5 : 4
        }
        func refreshStyles() {
            guard let map = host?.map else { return }
            for overlay in map.overlays { if let renderer = map.renderer(for: overlay) as? MKPolylineRenderer { style(renderer) } }
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
        @objc func selectPoint(_ gesture: UITapGestureRecognizer) {
            guard let host else { return }
            let location = gesture.location(in: host.map)
            selectedPoint = host.renderer?.nearest(to: location)
            if selectedPoint == nil {
                var distance = 28.0
                for point in points {
                    let screen = host.map.convert(mapCoordinate(point.coordinate), toPointTo: host.map)
                    let delta = hypot(screen.x-location.x,screen.y-location.y)
                    if delta < distance { distance = delta; selectedPoint = point }
                }
            }
            updateReading()
        }
        func updateReading() {
            guard let label = host?.reading else { return }
            guard let point = selectedPoint else { label.isHidden = true; return }
            guard let altitude = point.altitude else { label.text = "高度未知 · 保留平面位置"; label.isHidden = false; return }
            let value = Display.number(units.altitude(altitude), decimals: 0)
            label.text = "高度 \(value) \(units.altitudeLabel) · \(point.estimated == true ? "估计" : "记录值")\(altitude < 0 ? " · 零平面以下" : "")"
            if altitudeReference == "unknown" { label.text = (label.text ?? "") + " · 高度基准未知" }
            label.isHidden = false
        }
        func fitHeightIfNeeded() {
            guard let host, let renderer = host.renderer, renderer.ready else { return }
            if needsPitchedView {
                needsPitchedView = false
                // MapKit can force a nadir view at flight-wide zoom levels (notably on iPhone).
                // Enter an honest pitched detail view instead of presenting a flat overview as 3D.
                if host.map.camera.pitch < 10,
                   let highest = renderer.scene.vertices.max(by: { $0.position.z < $1.position.z }) {
                    let camera = host.map.camera.copy() as! MKMapCamera
                    camera.centerCoordinate = mapCoordinate(highest.point.coordinate)
                    camera.altitude = max(60_000, max(abs(renderer.scene.minimumHeight), renderer.scene.maximumHeight) * 3 + 300)
                    camera.pitch = 55
                    heightFitAttempts = 0
                    renderer.detailView = true
                    host.map.setCamera(camera, animated: false)
                    return
                }
            }
            guard heightFitAttempts > 0 else { return }
            renderer.detailView = false
            heightFitAttempts -= 1
            let map = host.map, bounds = map.bounds
            let left = bounds.width > 700 ? min(410, bounds.width*0.46) : 35
            let safe = bounds.inset(by: UIEdgeInsets(top: min(95,bounds.height*0.2), left: left,
                bottom: min(85,bounds.height*0.18), right: 70))
            let elevated = renderer.scene.vertices.compactMap { renderer.projected($0) }
            let ground = renderer.scene.vertices.map { vertex in
                map.convert(mapCoordinate(vertex.point.coordinate), toPointTo: map)
            }
            // A partly clipped high route must first move in front of the camera.
            if elevated.count != renderer.scene.vertices.count {
                let camera = map.camera.copy() as! MKMapCamera
                camera.altitude *= 2
                map.setCamera(camera, animated: false)
                return
            }
            guard !elevated.isEmpty else { return }
            let projected = (elevated + ground).map { SIMD2(Double($0.x), Double($0.y)) }
            guard let fit = RouteViewportFit.adjustment(points: projected,
                minimum: SIMD2(Double(safe.minX), Double(safe.minY)),
                maximum: SIMD2(Double(safe.maxX), Double(safe.maxY))) else {
                heightFitAttempts = 0; return
            }
            let camera = map.camera.copy() as! MKMapCamera
            let shift = CGPoint(x: bounds.midX + fit.centerOffset.x, y: bounds.midY + fit.centerOffset.y)
            camera.centerCoordinate = map.convert(shift, toCoordinateFrom: map)
            let minimumAltitude = max(abs(renderer.scene.minimumHeight), renderer.scene.maximumHeight) * 2 + 300
            camera.altitude = max(minimumAltitude, camera.altitude * fit.scale)
            map.setCamera(camera, animated: false)
        }
    }
}


final class RouteMapContainer: UIView {
    let map = MKMapView()
    var renderer: RouteAltitudeRenderer?
    let status = UILabel()
    let reading = UILabel()
    private lazy var compass = MKCompassButton(mapView: map)
    override init(frame: CGRect) {
        super.init(frame: frame); addSubview(map)
        renderer = RouteAltitudeRenderer(map: map)
        if let renderer { addSubview(renderer.view) }
        compass.compassVisibility = .adaptive; addSubview(compass)
        for label in [status, reading] {
            label.font = .preferredFont(forTextStyle: .caption2)
            label.adjustsFontForContentSizeCategory = true; label.textColor = .white
            label.backgroundColor = UIColor.black.withAlphaComponent(0.72)
            label.layer.cornerRadius = 7; label.clipsToBounds = true
            label.numberOfLines = 2; label.textAlignment = .center; label.isHidden = true
            label.isUserInteractionEnabled = false; addSubview(label)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews(); map.frame = bounds; renderer?.view.frame = bounds
        // Keep Apple's own attribution and legal controls unobscured at the bottom edge.
        compass.frame = CGRect(x:bounds.width-54,y:bounds.height-88,width:40,height:40)
        let width = min(420, max(120,bounds.width-100))
        status.frame = CGRect(x:(bounds.width-width)/2,y:bounds.height-64,width:width,height:32)
        reading.frame = CGRect(x:(bounds.width-width)/2,y:bounds.height-102,width:width,height:34)
    }
}
