#if canImport(MAMapKit) && !targetEnvironment(simulator)
import SwiftUI
import MAMapKit
import AMapFoundationKit

enum AMapSetup {
    static func initialize() {
        MAMapView.updatePrivacyShow(.didShow, privacyInfo:.didContain)
        MAMapView.updatePrivacyAgree(.didAgree)
        AMapServices.shared().apiKey = MapPreferences.key("AMapAPIKey")!
        AMapServices.shared().enableHTTPS = true
    }
    static func coordinate(_ value:Coordinate) -> CLLocationCoordinate2D {
        AMapCoordinateConvert(CLLocationCoordinate2D(latitude:value.latitude,longitude:value.longitude),.GPS)
    }
}
struct AMapRouteMap: UIViewRepresentable {
    var points:[TrackPoint]; var satellite:Bool; var perspective:Bool; var resetToken:Int; var follow:Bool
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context:Context) -> MAMapView {
        AMapSetup.initialize()
        let map = MAMapView(frame:.zero)
        map.delegate = context.coordinator; map.showsCompass = false; map.showsScale = true; map.isRotateEnabled = false
        map.mapType = .standardNight; map.zoomLevel = 13
        map.centerCoordinate = AMapSetup.coordinate(Coordinate(32.076,118.792))
        return map
    }
    func updateUIView(_ map:MAMapView,context:Context) {
        map.mapType = satellite ? .satellite : .standardNight
        let c = context.coordinator
        if c.lastID != points.last?.id || c.count != points.count {
            c.lastID = points.last?.id; c.count = points.count
            map.removeOverlays(map.overlays); map.removeAnnotations(map.annotations)
            for segment in grouped(points) {
                var coordinates = segment.map { AMapSetup.coordinate($0.coordinate) }
                if let line = MAPolyline(coordinates:&coordinates,count:UInt(coordinates.count)) { map.add(line) }
            }
            for (p,title) in [(points.first,"起点"),(points.last,"当前位置")] {
                if let p { let marker = MAPointAnnotation(); marker.coordinate = AMapSetup.coordinate(p.coordinate); marker.title = title; map.addAnnotation(marker) }
            }
            if follow,let p = points.last { map.setCenter(AMapSetup.coordinate(p.coordinate),animated:true) }
        }
        if c.reset != resetToken || !c.fitted && !points.isEmpty {
            c.reset = resetToken; c.fitted = !points.isEmpty
            if !map.overlays.isEmpty { map.showOverlays(map.overlays,edgePadding:UIEdgeInsets(top:65,left:40,bottom:40,right:65),animated:true) }
        }
        if c.perspective != perspective { c.perspective = perspective; map.setCameraDegree(perspective ? 45 : 0,animated:true,duration:0.3) }
    }
    class Coordinator: NSObject,MAMapViewDelegate {
        var lastID:UUID?; var count = -1; var reset = -1; var fitted = false; var perspective = false
        func mapView(_ mapView:MAMapView!,rendererFor overlay:MAOverlay!) -> MAOverlayRenderer! {
            guard let line = overlay as? MAPolyline else { return nil }
            let renderer = MAPolylineRenderer(polyline:line)!
            renderer.strokeColor = UIColor(Theme.accent); renderer.lineWidth = 4
            return renderer
        }
        func mapView(_ mapView:MAMapView!,viewFor annotation:MAAnnotation!) -> MAAnnotationView! {
            let view = MAPinAnnotationView(annotation:annotation,reuseIdentifier:"point")!
            view.pinColor = .purple; view.canShowCallout = true; return view
        }
    }
}
struct AMapOfflineManager: UIViewControllerRepresentable {
    func makeUIViewController(context:Context) -> UINavigationController {
        AMapSetup.initialize()
        return UINavigationController(rootViewController:MAOfflineMapViewController.sharedInstance())
    }
    func updateUIViewController(_ view:UIViewControllerType,context:Context) {}
}
#endif
