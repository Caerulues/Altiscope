#if canImport(GoogleMaps)
import SwiftUI
import GoogleMaps

struct GoogleRouteMap: UIViewRepresentable {
    var points: [TrackPoint]; var satellite: Bool; var perspective: Bool; var resetToken: Int; var follow: Bool
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> GMSMapView {
        GMSServices.provideAPIKey(MapPreferences.key("GoogleMapsAPIKey")!)
        let options = GMSMapViewOptions()
        options.camera = GMSCameraPosition(latitude:32.076,longitude:118.792,zoom:13)
        let map = GMSMapView(options:options)
        map.overrideUserInterfaceStyle = .dark; map.settings.compassButton = false; map.settings.rotateGestures = false
        map.padding = UIEdgeInsets(top:60,left:8,bottom:8,right:8)
        let style = ##"[{"elementType":"geometry","stylers":[{"color":"#18202b"}]},{"elementType":"labels.text.fill","stylers":[{"color":"#7c8999"}]},{"elementType":"labels.text.stroke","stylers":[{"color":"#18202b"}]},{"featureType":"water","elementType":"geometry","stylers":[{"color":"#0d141e"}]},{"featureType":"road","elementType":"geometry","stylers":[{"color":"#2b3543"}]},{"featureType":"poi","stylers":[{"visibility":"off"}]}]"##
        map.mapStyle = try? GMSMapStyle(jsonString:style)
        return map
    }
    func updateUIView(_ map:GMSMapView,context:Context) {
        map.mapType = satellite ? .satellite : .normal
        let c = context.coordinator
        if c.lastID != points.last?.id || c.count != points.count {
            c.lastID = points.last?.id; c.count = points.count; map.clear()
            for segment in grouped(points) {
                let path = GMSMutablePath()
                for point in segment { path.addLatitude(point.coordinate.latitude,longitude:point.coordinate.longitude) }
                let line = GMSPolyline(path:path); line.strokeColor = UIColor(Theme.accent); line.strokeWidth = 4; line.map = map
            }
            for (point,title,color) in [(points.first,"起点",Theme.mint),(points.last,"当前位置",Theme.accent)] {
                if let point { let marker = GMSMarker(position:CLLocationCoordinate2D(latitude:point.coordinate.latitude,longitude:point.coordinate.longitude)); marker.title = title; marker.icon = GMSMarker.markerImage(with:UIColor(color)); marker.map = map }
            }
            if follow, let p = points.last { map.animate(toLocation:CLLocationCoordinate2D(latitude:p.coordinate.latitude,longitude:p.coordinate.longitude)) }
        }
        if c.reset != resetToken || !c.fitted && !points.isEmpty {
            c.reset = resetToken; c.fitted = !points.isEmpty
            if let first = points.first {
                var bounds = GMSCoordinateBounds(coordinate:CLLocationCoordinate2D(latitude:first.coordinate.latitude,longitude:first.coordinate.longitude),coordinate:CLLocationCoordinate2D(latitude:first.coordinate.latitude,longitude:first.coordinate.longitude))
                for p in points { bounds = bounds.includingCoordinate(CLLocationCoordinate2D(latitude:p.coordinate.latitude,longitude:p.coordinate.longitude)) }
                map.animate(with:GMSCameraUpdate.fit(bounds,withPadding:55))
            }
        }
        if c.perspective != perspective { c.perspective = perspective; map.animate(toViewingAngle:perspective ? 50 : 0) }
    }
    class Coordinator { var lastID:UUID?; var count = -1; var reset = -1; var fitted = false; var perspective = false }
}
struct GoogleLegalView: View {
    @State private var show = false
    var body: some View {
        Button("Google Maps 开源许可") { show = true }.font(.system(size:12))
            .sheet(isPresented:$show) { NavigationStack { ScrollView { Text(GMSServices.openSourceLicenseInfo()).font(.system(size:11)).padding() }.navigationTitle("第三方许可").toolbar { Button("完成") { show = false } } } }
    }
}
#endif
