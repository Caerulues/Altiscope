import SwiftUI
import CoreLocation
import CoreMotion
import Network

@MainActor final class Recorder: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var sessions: [TrackSession] = []
    @Published var active: TrackSession?
    @Published var selected: TrackSession?
    @Published var location: CLLocation?
    @Published var heading: Double?
    @Published var headingReference = "磁北"
    @Published var acceleration: MotionSample?
    @Published var sensorMessage = "开始记录后启用传感器"
    @Published var message: String?
    @Published var isOnline = true
    @Published var now = Date()
    @Published var authorization: CLAuthorizationStatus = .notDetermined
    @Published var reducedAccuracy = false
    @Published var mode: TravelMode = .walking
    @Published var shareURL: URL?
    private let manager = CLLocationManager()
    private let motion = CMMotionManager()
    private let monitor = NWPathMonitor()
    private var store: TrackStore?
    private var timer: Timer?
    private var pendingStart = false
    private var lastMotionUI = Date.distantPast
    private var lastMotionWrite = Date.distantPast
    private var headingDate = Date.distantPast
    private var previewing = false

    var displayed: TrackSession? { selected ?? active }
    var isRecording: Bool { active?.state == .recording }
    var hasFreshFix: Bool { location.map { now.timeIntervalSince($0.timestamp) < 15 && $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 65 } ?? false }
    var freshHeading: Double? { now.timeIntervalSince(headingDate) < 5 ? heading : nil }
    var freshAcceleration: MotionSample? { acceleration.flatMap { now.timeIntervalSince($0.timestamp) < 2 ? $0 : nil } }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        authorization = manager.authorizationStatus
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Antiscope/Tracks")
            store = try TrackStore(directory: directory)
            let loaded = try store!.load()
            sessions = loaded.sessions
            active = sessions.first(where: { $0.state != .finished })
            if !loaded.warnings.isEmpty { message = loaded.warnings.joined(separator: "\n") }
        } catch { message = "本地存储不可用：\(error.localizedDescription)" }
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async { self?.isOnline = path.status == .satisfied }
        }
        monitor.start(queue: DispatchQueue(label: "app.antiscope.network"))
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
        if ProcessInfo.processInfo.arguments.contains("--demo") { showDemo() }
    }

    func start() {
        guard store != nil else { message = "无法创建本地记录，请检查设备存储空间。"; return }
        selected = nil; previewing = false
        if active?.state == .recording { return }
        pendingStart = true
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: beginAuthorized()
        case .notDetermined: manager.requestWhenInUseAuthorization()
        default: pendingStart = false; message = "定位权限未开启。请在系统设置中允许 Antiscope 使用精确位置。"
        }
    }

    private func beginAuthorized() {
        guard pendingStart else { return }; pendingStart = false
        do {
            if active?.state == .paused { active?.resume() }
            else { active = TrackSession(title: "\(mode.title) · \(Date().formatted(date: .abbreviated, time: .shortened))", mode: mode) }
            try store?.saveMetadata(active!)
            location = nil; heading = nil; acceleration = nil
            manager.activityType = active?.mode == .flight ? .airborne : active?.mode == .driving ? .automotiveNavigation : .fitness
            manager.allowsBackgroundLocationUpdates = true
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
            startMotion()
        } catch { storageFailed(error) }
    }

    private func startMotion() {
        guard motion.isDeviceMotionAvailable else { sensorMessage = "此设备没有可用的运动传感器"; return }
        sensorMessage = "正在读取加速度"
        motion.deviceMotionUpdateInterval = 1.0 / 20
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] data, error in
            guard let self else { return }
            if let error { self.sensorMessage = "运动数据不可用：\(error.localizedDescription)"; return }
            guard let data, self.isRecording else { return }
            // Core Motion timestamps are monotonic; do not relabel delayed samples as current.
            let date = Date().addingTimeInterval(data.timestamp - ProcessInfo.processInfo.systemUptime)
            guard abs(date.timeIntervalSinceNow) < 2 else { return }
            let a = data.userAcceleration
            let sample = MotionSample(timestamp: date, x: a.x * 9.80665, y: a.y * 9.80665, z: a.z * 9.80665)
            if date.timeIntervalSince(self.lastMotionUI) >= 0.2 {
                self.acceleration = sample; self.lastMotionUI = date; self.sensorMessage = "加速度计 · 已连接"
            }
            if date.timeIntervalSince(self.lastMotionWrite) >= 1, let id = self.active?.id {
                do {
                    try self.store?.appendMotion(sample, id: id)
                    self.active?.motion.append(sample); self.lastMotionWrite = date
                } catch { self.storageFailed(error) }
            }
        }
    }

    func pause() {
        guard active?.state == .recording else { return }
        active?.pause(); stopSensors()
        do { try store?.saveMetadata(active!); syncSession() } catch { storageFailed(error) }
    }

    func finish() {
        guard var completed = active else { return }
        completed.finish(); stopSensors()
        do {
            try store?.saveMetadata(completed); active = completed; syncSession()
            selected = active; active = nil
        } catch { storageFailed(error) }
    }

    func returnToLive() { selected = nil; previewing = false }
    func showDemo() { selected = DemoRoute.make(); previewing = true }
    func select(_ session: TrackSession) {
        if session.id == active?.id { selected = nil } else { selected = session }
    }
    func updateNotes(_ notes: String, title: String) {
        guard var session = displayed, !session.isDemo else { return }
        session.notes = notes; session.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? session.title : title
        do {
            try store?.saveMetadata(session)
            if active?.id == session.id { active?.title = session.title; active?.notes = notes }
            if selected?.id == session.id { selected = session }
            if let index = sessions.firstIndex(where: { $0.id == session.id }) { sessions[index] = session }
        } catch { message = "保存笔记失败：\(error.localizedDescription)" }
    }
    func export(gpx: Bool) {
        guard let session = displayed else { return }
        do { shareURL = try store?.writeExport(session, gpx: gpx, to: FileManager.default.temporaryDirectory.appendingPathComponent("AntiscopeExports")) }
        catch { message = "导出失败：\(error.localizedDescription)" }
    }
    private func stopSensors() {
        manager.stopUpdatingLocation(); manager.stopUpdatingHeading(); manager.allowsBackgroundLocationUpdates = false
        motion.stopDeviceMotionUpdates(); sensorMessage = "传感器已暂停"
    }
    private func syncSession() {
        guard let active else { return }
        if let i = sessions.firstIndex(where: { $0.id == active.id }) { sessions[i] = active }
        else { sessions.insert(active, at: 0) }
    }
    private func storageFailed(_ error: Error) {
        active?.pause(); stopSensors()
        message = "写入失败，记录已暂停以保护数据。\(error.localizedDescription)"
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        reducedAccuracy = manager.accuracyAuthorization == .reducedAccuracy
        if authorization == .authorizedWhenInUse || authorization == .authorizedAlways { beginAuthorized() }
        else if authorization == .denied || authorization == .restricted {
            pendingStart = false
            if isRecording { pause(); message = "定位权限已关闭，记录已暂停。" }
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isRecording else { return }
        for fix in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard fix.horizontalAccuracy >= 0 else { continue }
            if location == nil || fix.timestamp > location!.timestamp { location = fix }
            let point = TrackPoint(timestamp: fix.timestamp, coordinate: Coordinate(fix.coordinate.latitude, fix.coordinate.longitude),
                altitude: fix.verticalAccuracy >= 0 ? fix.altitude : nil, speed: fix.speed >= 0 ? fix.speed : nil,
                course: fix.course >= 0 ? fix.course : nil, heading: freshHeading,
                horizontalAccuracy: fix.horizontalAccuracy, verticalAccuracy: fix.verticalAccuracy >= 0 ? fix.verticalAccuracy : nil)
            if let accepted = active?.ingest(point), let session = active {
                do { try store?.appendPoint(accepted, session: session) }
                catch { storageFailed(error); break }
            }
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        headingReference = newHeading.trueHeading >= 0 ? "真北" : "磁北"
        headingDate = newHeading.timestamp
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let error = error as? CLError, error.code == .locationUnknown { return }
        message = "定位暂不可用：\(error.localizedDescription)"
    }
}
