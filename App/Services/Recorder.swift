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
    @Published var sensorMessage = "开始记录后启用运动传感器"
    @Published var locationMessage = "正在获取当前位置"
    @Published var message: String?
    @Published var isOnline = true
    @Published var now = Date()
    @Published var authorization: CLAuthorizationStatus = .notDetermined
    @Published var reducedAccuracy = false
    @Published var mode: TravelMode = .walking
    @Published var shareURL: URL?
    @Published var cameraRequest = 0
    @Published var followLocation = true
    @Published var panelExpanded = true
    @Published var panelPosition = CGPoint(x: 16, y: 100)
    private let manager = CLLocationManager()
    private let motion = CMMotionManager()
    private let monitor = NWPathMonitor()
    private var store: TrackStore?
    private var timer: Timer?
    private var pendingStart = false
    private var pendingPreview = false
    private var previewDeadline: Date?
    private var headingDate = Date.distantPast
    private var lastMotionUI = 0.0
    private var lastSampleTime = 0.0
    private var lastMotionTime = 0.0
    private var pendingMotion: [MotionSample] = []
    private var pendingLocations: [GPSObservation] = []
    private var latestGPS = GPSObservation()
    private var navigator = InertialNavigator()
    private var experimental = false
    private var lastPositionTime: Date?
    private var lastUsedInertial: Bool?
    private var locationFilter: TrackSession?
    private var distanceBeforeInterval = 0.0
    private var trueNorthMotion = false

    var displayed: TrackSession? { selected ?? active }
    var isRecording: Bool { active?.state == .recording }
    var hasFreshFix: Bool { location.map { (0...15).contains(now.timeIntervalSince($0.timestamp)) && (0...65).contains($0.horizontalAccuracy) } ?? false }
    var freshHeading: Double? { (0...5).contains(now.timeIntervalSince(headingDate)) ? heading : nil }
    var freshAcceleration: MotionSample? { acceleration.flatMap { (0...2).contains(now.timeIntervalSince($0.timestamp)) ? $0 : nil } }
    var compass: CompassObservation? { freshHeading.map { CompassObservation(degrees: $0, trueNorth: headingReference == "真北", timestamp: headingDate) } }

    override init() {
        super.init()
        manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone; manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true; authorization = manager.authorizationStatus
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Altiscope/Tracks")
            let store = try TrackStore(directory: directory); self.store = store
            let loaded = try store.load(); sessions = loaded.sessions; active = sessions.first { $0.state != .finished }
            if !loaded.warnings.isEmpty { message = loaded.warnings.joined(separator: "\n") }
        } catch { message = "本地存储不可用：\(error.localizedDescription)" }
        monitor.pathUpdateHandler = { [weak self] path in DispatchQueue.main.async { self?.isOnline = path.status == .satisfied } }
        monitor.start(queue: DispatchQueue(label: "app.altiscope.network"))
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        if ProcessInfo.processInfo.arguments.contains("--demo") { showDemo() }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo-altitude") { selected = DemoRoute.altitudePreview(); overview() }
        #endif
    }
    private func tick() {
        now = Date()
        if let deadline = previewDeadline, now >= deadline { previewDeadline = nil; locationMessage = "定位超时，可点定位按钮重试" }
        if !isRecording, let location, Date().timeIntervalSince(location.timestamp) > 15 { locationMessage = "最近一次位置已过期，点定位按钮刷新" }
        if isRecording { persistSample() }
    }
    func requestPreview() {
        guard selected == nil else { return }
        guard CLLocationManager.locationServicesEnabled() else { locationMessage = "系统定位服务已关闭"; return }
        pendingPreview = true
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            pendingPreview = false
            guard !isRecording else { return }
            previewDeadline = Date().addingTimeInterval(15); locationMessage = reducedAccuracy ? "正在获取大致位置" : "正在获取当前位置"
            manager.requestLocation()
        case .notDetermined: locationMessage = "等待定位授权"; manager.requestWhenInUseAuthorization()
        default: pendingPreview = false; locationMessage = "定位权限未开启，请在系统设置中允许定位"
        }
    }
    func recenter() { followLocation = true; cameraRequest += 1; requestPreview() }
    func overview() { followLocation = false; cameraRequest += 1 }
    func start() {
        guard store != nil else { message = "无法创建本地记录，请检查存储空间"; return }
        selected = nil
        guard !isRecording else { return }
        pendingStart = true
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: beginAuthorized()
        case .notDetermined: manager.requestWhenInUseAuthorization()
        default: pendingStart = false; message = "定位权限未开启，请在系统设置中允许定位"
        }
    }
    private func beginAuthorized() {
        guard pendingStart, let store else { return }; pendingStart = false
        do {
            if active?.state == .paused { active?.resume() }
            else { active = TrackSession(title: "\(mode.title) · \(Date().formatted(date: .abbreviated, time: .shortened))", mode: mode); active?.navigationSamples = [] }
            try store.saveMetadata(active!)
            navigator.reset(segmentId: active!.segment); pendingMotion = []; pendingLocations = []; latestGPS = GPSObservation()
            lastSampleTime = ProcessInfo.processInfo.systemUptime; lastMotionTime = 0; lastPositionTime = nil; lastUsedInertial = nil
            locationFilter = TrackSession(title: "quality filter", mode: active!.mode)
            distanceBeforeInterval = active!.distance
            location = nil; heading = nil; acceleration = nil
            experimental = UserDefaults.standard.bool(forKey: "experimentalInertialNavigation")
            manager.activityType = active?.mode == .flight ? .airborne : active?.mode == .driving ? .automotiveNavigation : .fitness
            manager.allowsBackgroundLocationUpdates = true; manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
            startMotion(); recenter()
        } catch { storageFailed(error) }
    }
    private func startMotion() {
        guard motion.isDeviceMotionAvailable else { sensorMessage = "运动传感器不可用，使用定位观测记录"; return }
        trueNorthMotion = CMMotionManager.availableAttitudeReferenceFrames().contains(.xTrueNorthZVertical)
        let reference: CMAttitudeReferenceFrame = trueNorthMotion ? .xTrueNorthZVertical : .xArbitraryZVertical
        sensorMessage = experimental && trueNorthMotion ? "实验惯导 · 尚未经真机标定" : "记录原始运动数据"
        motion.deviceMotionUpdateInterval = 1.0 / 20
        motion.startDeviceMotionUpdates(using: reference, to: .main) { [weak self] data, error in
            guard let self, self.isRecording else { return }
            if let error { self.sensorMessage = "运动数据不可用：\(error.localizedDescription)"; return }
            guard let data else { return }
            let uptime = ProcessInfo.processInfo.systemUptime
            guard (0...0.5).contains(uptime - data.timestamp), data.timestamp > self.lastMotionTime else { return }
            let date = Date().addingTimeInterval(data.timestamp - uptime)
            let a = data.userAcceleration, r = data.attitude.rotationMatrix, rate = data.rotationRate
            var sample = MotionSample(timestamp: date, x: a.x * 9.80665, y: a.y * 9.80665, z: a.z * 9.80665)
            sample.monotonicTime = data.timestamp; sample.rotationMatrix = [r.m11,r.m12,r.m13,r.m21,r.m22,r.m23,r.m31,r.m32,r.m33]
            sample.rotationRate = [rate.x, rate.y, rate.z]; sample.attitudeReference = self.trueNorthMotion ? "north_west_up" : "arbitrary_z_vertical"
            self.pendingMotion.append(sample); self.lastMotionTime = data.timestamp
            if data.timestamp - self.lastMotionUI >= 0.2 { self.acceleration = sample; self.lastMotionUI = data.timestamp }
            if self.experimental && self.trueNorthMotion && data.magneticField.accuracy != .uncalibrated {
                let enu = InertialNavigator.accelerationENU(device: VectorENU(east: sample.x, north: sample.y, up: sample.z), rotation: sample.rotationMatrix!)
                self.navigator.predict(acceleration: enu, monotonicTime: data.timestamp, timestamp: date, compass: self.compass)
                self.navigator.correct(self.latestGPS, monotonicTime: data.timestamp, timestamp: date, mode: self.active!.mode, compass: self.compass)
                self.sensorMessage = "实验惯导 · 尚未经真机标定"
            } else if self.experimental {
                self.navigator.reset(segmentId: max(self.navigator.segmentId, self.active!.segment))
                self.sensorMessage = "方向参考未校准，使用定位观测记录"
            }
            if uptime - self.lastSampleTime >= 1 { self.persistSample() }
        }
    }
    private func persistSample(force: Bool = false) {
        guard var session = active, session.state == .recording, let store else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        guard force || uptime - lastSampleTime >= 0.9 else { return }
        let date = Date()
        var inertial = experimental && trueNorthMotion && uptime - lastMotionTime < 0.5 ? navigator.state : InertialState()
        if experimental && uptime - lastMotionTime >= 0.5 { inertial.status = .invalid; navigator.reset(segmentId: max(navigator.segmentId, session.segment)) }
        let gps = latestGPS.fresh(at: date)
        let usesInertial = inertial.coordinate != nil && [.corrected, .predicted].contains(inertial.status)
        var segment = max(session.segment, navigator.segmentId)
        if let previous = lastUsedInertial, previous != usesInertial { segment += 1 }
        if let lastPositionTime, date.timeIntervalSince(lastPositionTime) > 15 { segment += 1; self.lastPositionTime = nil }
        var sample = NavigationSample(sequence: (session.navigationSamples?.last?.sequence ?? session.points.count) + 1,
            segmentId: segment, timestamp: date, inertial: inertial, gps: gps, rawMotion: pendingMotion)
        sample.rawLocations = pendingLocations
        session.appendNavigation(sample)
        if !experimental { session.distance = distanceBeforeInterval + (locationFilter?.distance ?? 0) }
        sample.cumulativeDistanceM = session.distance
        let sampleIndex = (session.navigationSamples?.count ?? 1) - 1
        session.navigationSamples?[sampleIndex] = sample
        do {
            try store.appendSample(sample, id: session.id)
            active = session; pendingMotion = []; pendingLocations = []; lastSampleTime = uptime
            if sample.displayCoordinate != nil { lastPositionTime = date; lastUsedInertial = usesInertial }
        } catch { storageFailed(error) }
    }
    func pause() {
        guard isRecording else { return }
        persistSample(force: true); active?.pause(); stopSensors()
        do { if let active { try store?.saveMetadata(active) }; syncSession() } catch { storageFailed(error) }
    }
    func finish() {
        if isRecording { persistSample(force: true) }
        guard var completed = active, let store else { return }
        completed.finish(); stopSensors()
        do { try store.saveMetadata(completed); active = completed; syncSession(); selected = completed; active = nil; overview() }
        catch { storageFailed(error) }
    }
    func returnToLive() { selected = nil; recenter() }
    func showDemo() { selected = DemoRoute.make(); overview() }
    func select(_ session: TrackSession) { selected = session.id == active?.id ? nil : session; selected == nil ? recenter() : overview() }
    @discardableResult func updateNotes(_ notes: String, title: String) -> Bool {
        guard var session = displayed, !session.isDemo, let store else { return false }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { message = "名称不能为空"; return false }
        session.notes = notes; session.title = name
        do {
            try store.saveMetadata(session)
            if active?.id == session.id { active?.title = name; active?.notes = notes }
            updateVisible(session); return true
        } catch { message = "保存失败：\(error.localizedDescription)"; return false }
    }
    @discardableResult func manage(_ original: TrackSession, name: String, mode: TravelMode, notes: String) -> Bool {
        guard original.state == .finished, original.id != active?.id, let store else { message = "请先结束当前旅程再管理"; return false }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { message = "名称不能为空"; return false }
        var session = sessions.first { $0.id == original.id } ?? original
        session.title = name; session.mode = mode; session.notes = notes
        do { try store.saveMetadata(session); updateVisible(session); return true }
        catch { message = "保存失败：\(error.localizedDescription)"; return false }
    }
    @discardableResult func delete(_ session: TrackSession) -> Bool {
        guard session.state == .finished, session.id != active?.id, let store else { message = "请先结束当前旅程再删除"; return false }
        do {
            try store.delete(session.id); sessions.removeAll { $0.id == session.id }
            if selected?.id == session.id { returnToLive() }; return true
        } catch { message = "删除失败：\(error.localizedDescription)"; return false }
    }
    func isDuplicate(_ document: TrackDocument) -> Bool {
        sessions.contains { session in
            let source = document.metadata.provenance?.sourceID ?? document.metadata.sessionId
            return session.id == source || session.provenance?.sourceID == source ||
                (document.metadata.provenance?.fingerprint != nil && session.provenance?.fingerprint == document.metadata.provenance?.fingerprint)
        }
    }
    func commitImport(_ documents: [TrackDocument]) throws {
        guard let store else { throw TrackFileError.invalid("本地存储不可用") }
        sessions += try store.importDocuments(documents)
        sessions.sort { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
    }
    func export(gpx: Bool) {
        guard let session = displayed else { return }
        do { shareURL = try store?.writeExport(session, gpx: gpx, to: FileManager.default.temporaryDirectory.appendingPathComponent("AltiscopeExports")) }
        catch { message = "导出失败：\(error.localizedDescription)" }
    }
    private func updateVisible(_ session: TrackSession) {
        if selected?.id == session.id { selected = session }
        if let index = sessions.firstIndex(where: { $0.id == session.id }) { sessions[index] = session }
    }
    private func stopSensors() {
        manager.stopUpdatingLocation(); manager.stopUpdatingHeading(); manager.allowsBackgroundLocationUpdates = false
        motion.stopDeviceMotionUpdates(); sensorMessage = "运动传感器已暂停"
    }
    private func syncSession() {
        guard let active else { return }
        if let index = sessions.firstIndex(where: { $0.id == active.id }) { sessions[index] = active } else { sessions.insert(active, at: 0) }
    }
    private func storageFailed(_ error: Error) { active?.pause(); stopSensors(); message = "写入失败，记录已暂停。\(error.localizedDescription)" }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus; reducedAccuracy = manager.accuracyAuthorization == .reducedAccuracy
        if authorization == .authorizedWhenInUse || authorization == .authorizedAlways { beginAuthorized(); if pendingPreview { requestPreview() } }
        else if authorization == .denied || authorization == .restricted {
            pendingStart = false; pendingPreview = false; locationMessage = "定位权限未开启"
            if isRecording { pause(); message = "定位权限已关闭，记录已暂停" }
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for fix in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
            let fresh = (-2...15).contains(Date().timeIntervalSince(fix.timestamp))
            var observation = GPSObservation(measuredCoordinate: Coordinate(fix.coordinate.latitude, fix.coordinate.longitude),
                observedAt: fix.timestamp, horizontalAccuracyM: fix.horizontalAccuracy, altitudeM: fix.altitude,
                verticalAccuracyM: fix.verticalAccuracy, speedMps: fix.speed, courseDeg: fix.course)
            if fresh && observation.coordinate != nil && (location == nil || fix.timestamp > location!.timestamp) {
                location = fix; previewDeadline = nil
                locationMessage = reducedAccuracy ? "大致位置 · 可在设置启用精确定位" : fix.horizontalAccuracy <= 65 ? "当前位置已更新" : "定位精度较低，等待更准确位置"
            }
            guard isRecording else { continue }
            observation.deviceHeadingDeg = freshHeading
            observation.deviceHeadingReference = freshHeading == nil ? nil : (headingReference == "真北" ? "true_north" : "magnetic_north")
            observation.usableForRoute = false
            if fresh && (latestGPS.observedAt.map({ fix.timestamp > $0 }) ?? true) {
                if let coordinate = observation.coordinate {
                    let point = TrackPoint(timestamp: fix.timestamp, coordinate: coordinate, altitude: observation.altitudeM,
                        speed: observation.speedMps, course: observation.courseDeg, heading: freshHeading,
                        horizontalAccuracy: observation.horizontalAccuracyM, verticalAccuracy: observation.verticalAccuracyM)
                    observation.usableForRoute = locationFilter?.ingest(point) != nil
                }
                latestGPS = observation
            }
            pendingLocations.append(observation)
            // Keep only filter state; raw observations are retained in navigation samples.
            if let last = locationFilter?.points.last { locationFilter?.points = [last] }
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        headingReference = newHeading.trueHeading >= 0 ? "真北" : "磁北"; headingDate = newHeading.timestamp
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationMessage = "定位暂不可用，可点定位按钮重试"
        if let error = error as? CLError, error.code == .locationUnknown { return }
        message = "定位暂不可用：\(error.localizedDescription)"
    }
}
