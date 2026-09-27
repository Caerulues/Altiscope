import SwiftUI
import MapKit

struct RouteMapView: View {
    @EnvironmentObject var recorder: Recorder
    @EnvironmentObject var preferences: MapPreferences
    var resetToken: Int
    var follow: Bool
    var session: TrackSession? { recorder.displayed }
    var points: [TrackPoint] { RouteDisplay.sampled(session?.points ?? []) }
    var body: some View {
        Group {
            switch preferences.provider {
            case .apple: AppleRouteMap(points: points, satellite: preferences.satellite, perspective: preferences.perspective, resetToken: resetToken, follow: follow)
            case .google:
                #if canImport(GoogleMaps)
                if preferences.googleReady { GoogleRouteMap(points: points, satellite: preferences.satellite, perspective: preferences.perspective, resetToken: resetToken, follow: follow) }
                else { offline }
                #else
                offline
                #endif
            case .amap:
                #if canImport(MAMapKit) && !targetEnvironment(simulator)
                if preferences.amapReady { AMapRouteMap(points: points, satellite: preferences.satellite, perspective: preferences.perspective, resetToken: resetToken, follow: follow) }
                else { offline }
                #else
                offline
                #endif
            case .offline: offline
            }
        }.id("\(preferences.provider.rawValue)-\(session?.id.uuidString ?? "live")")
    }
    var offline: some View { OfflineCanvas(points: points, heading: recorder.freshHeading, resetToken: resetToken) }
}

struct AppleRouteMap: UIViewRepresentable {
    var points: [TrackPoint]; var satellite: Bool; var perspective: Bool; var resetToken: Int; var follow: Bool
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(); map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .dark; map.showsCompass = false; map.isRotateEnabled = false
        map.pointOfInterestFilter = .excludingAll
        map.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude:32.076,longitude:118.792), latitudinalMeters:6000,longitudinalMeters:6000), animated:false)
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
        map.mapType = satellite ? .satellite : .mutedStandard
        let c = context.coordinator
        if c.count != points.count || c.lastID != points.last?.id {
            c.count = points.count; c.lastID = points.last?.id
            map.removeOverlays(map.overlays); map.removeAnnotations(map.annotations)
            for group in grouped(points) {
                var coordinates = group.map { CLLocationCoordinate2D(latitude:$0.coordinate.latitude,longitude:$0.coordinate.longitude) }
                map.addOverlay(MKPolyline(coordinates:&coordinates,count:coordinates.count))
            }
            for (point,title) in [(points.first,"起点"),(points.last,"当前位置")] {
                if let point { let marker = MKPointAnnotation(); marker.coordinate = CLLocationCoordinate2D(latitude:point.coordinate.latitude,longitude:point.coordinate.longitude); marker.title = title; map.addAnnotation(marker) }
            }
            if follow, let last = points.last { map.setCenter(CLLocationCoordinate2D(latitude:last.coordinate.latitude,longitude:last.coordinate.longitude), animated:true) }
        }
        if c.reset != resetToken || !c.fitted && !points.isEmpty {
            c.reset = resetToken; c.fitted = !points.isEmpty
            var rect = map.overlays.reduce(MKMapRect.null) { $0.union($1.boundingMapRect) }
            if !rect.isNull {
                let minimum = MKMapPointsPerMeterAtLatitude(map.centerCoordinate.latitude) * 250
                rect = rect.insetBy(dx:-max(0,(minimum-rect.width)/2),dy:-max(0,(minimum-rect.height)/2))
                map.setVisibleMapRect(rect, edgePadding:UIEdgeInsets(top:60,left:40,bottom:45,right:60),animated:true)
            }
        }
        if c.perspective != perspective { c.perspective = perspective; let camera = map.camera.copy() as! MKMapCamera; camera.pitch = perspective ? 55 : 0; map.setCamera(camera,animated:true) }
    }
    class Coordinator: NSObject, MKMapViewDelegate {
        var count = -1; var lastID: UUID?; var reset = -1; var fitted = false; var perspective = false
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let renderer = MKPolylineRenderer(overlay:overlay); renderer.strokeColor = UIColor(Theme.accent); renderer.lineWidth = 4; renderer.lineCap = .round; return renderer
        }
    }
}
func grouped(_ points: [TrackPoint]) -> [[TrackPoint]] {
    var result: [[TrackPoint]] = []
    for p in points { if result.last?.last?.segment == p.segment { result[result.count-1].append(p) } else { result.append([p]) } }
    return result
}
