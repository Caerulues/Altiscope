import Foundation

/// A replayable, bounded complementary-filter prototype, not a calibrated navigation instrument.
public struct NavigationConfiguration: Sendable {
    public var correctionInterval = 5.0
    public var observationFreshness = 2.0
    public var maximumPredictionAge = 10.0
    public var maximumUncertainty = 80.0
    public var maximumMotionGap = 0.5
    public var minimumBearingSpeed = 0.5
    public init() {}
}
public struct CompassObservation: Sendable {
    public var degrees: Double
    public var trueNorth: Bool
    public var timestamp: Date
    public init(degrees: Double, trueNorth: Bool, timestamp: Date) { self.degrees = degrees; self.trueNorth = trueNorth; self.timestamp = timestamp }
}
public struct InertialNavigator: Sendable {
    public var configuration = NavigationConfiguration()
    public private(set) var state = InertialState()
    public private(set) var segmentId = 0
    private var lastTime: Double?
    private var correctedTime: Double?
    private var lastCheck: Double?
    private var lastObservation: Date?
    private var lastAccepted: GPSObservation?
    private var history: [(Date, Coordinate)] = []
    private var bias = VectorENU(east: 0, north: 0, up: 0)
    public init(segmentId: Int = 0) { self.segmentId = segmentId }
    public mutating func reset(segmentId: Int) { self = InertialNavigator(segmentId: segmentId) }
    public static func bearing(previous: VectorENU?, compass: CompassObservation?, at date: Date, minimumSpeed: Double = 0.5) -> (Double?, String?, String?) {
        if let previous, previous.isFinite, previous.horizontalSpeed >= minimumSpeed {
            return ((atan2(previous.east, previous.north) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360), "previous_velocity", "true_north")
        }
        if let compass, compass.degrees.isFinite, (0..<360).contains(compass.degrees), (0...5).contains(date.timeIntervalSince(compass.timestamp)) {
            return (compass.degrees, "compass", compass.trueNorth ? "true_north" : "magnetic_north")
        }
        return (nil, nil, nil)
    }
    /// Core Motion rotation transforms reference -> device. Its transpose transforms device -> reference.
    /// In xTrueNorthZVertical, reference axes are north, west, up. ENU is (-west, north, up).
    public static func accelerationENU(device: VectorENU, rotation: [Double]) -> VectorENU? {
        guard rotation.count == 9, rotation.allSatisfy(\.isFinite), device.isFinite else { return nil }
        let north = rotation[0] * device.east + rotation[3] * device.north + rotation[6] * device.up
        let west = rotation[1] * device.east + rotation[4] * device.north + rotation[7] * device.up
        let up = rotation[2] * device.east + rotation[5] * device.north + rotation[8] * device.up
        return VectorENU(east: -west, north: north, up: up)
    }
    private mutating func invalidate() {
        if state.coordinate != nil { segmentId += 1 }
        state = InertialState(); state.status = .invalid; history = []; lastTime = nil; correctedTime = nil
    }
    public mutating func predict(acceleration: VectorENU?, monotonicTime: Double, timestamp: Date, compass: CompassObservation?) {
        guard monotonicTime.isFinite, let acceleration, acceleration.isFinite else { invalidate(); return }
        defer { lastTime = monotonicTime }
        guard let previousTime = lastTime else { state.accelerationENU = acceleration; return }
        let dt = monotonicTime - previousTime
        guard dt > 0 else { return }
        guard dt <= configuration.maximumMotionGap else { invalidate(); return }
        guard let coordinate = state.coordinate, let velocity = state.velocityENU, let correctedTime else { state.accelerationENU = acceleration; return }
        let age = monotonicTime - correctedTime
        let uncertainty = (state.horizontalUncertaintyM ?? configuration.maximumUncertainty) + dt * (1 + age * 0.35)
        guard age <= configuration.maximumPredictionAge, uncertainty <= configuration.maximumUncertainty else { invalidate(); return }
        let direction = Self.bearing(previous: velocity, compass: compass, at: timestamp, minimumSpeed: configuration.minimumBearingSpeed)
        // Bias learning is gated by a fresh external near-zero velocity and low measured acceleration.
        // It is deliberately slow and disabled when external evidence is absent.
        if let observation = lastAccepted, let observedAt = observation.observedAt,
           (0...1).contains(timestamp.timeIntervalSince(observedAt)), (observation.speedMps ?? .infinity) < 0.2,
           hypot(acceleration.east, acceleration.north) < 0.15, abs(acceleration.up) < 0.15 {
            let gain = min(0.02, dt * 0.2)
            bias.east += gain * (acceleration.east - bias.east); bias.north += gain * (acceleration.north - bias.north)
            bias.up += gain * (acceleration.up - bias.up)
        }
        let a = VectorENU(east: acceleration.east - bias.east, north: acceleration.north - bias.north, up: acceleration.up - bias.up)
        let next = VectorENU(east: velocity.east + a.east * dt, north: velocity.north + a.north * dt, up: velocity.up + a.up * dt)
        let displacement = VectorENU(east: (velocity.east + next.east) * dt / 2, north: (velocity.north + next.north) * dt / 2, up: (velocity.up + next.up) * dt / 2)
        state.coordinate = Self.offset(coordinate, east: displacement.east, north: displacement.north)
        state.velocityENU = next; state.speedMps = next.horizontalSpeed; state.accelerationENU = acceleration
        if let altitude = state.altitudeM { state.altitudeM = altitude + displacement.up }
        state.bearingDeg = direction.0; state.bearingSource = direction.1; state.bearingReference = direction.2
        state.status = .predicted; state.predictionAgeSeconds = age; state.horizontalUncertaintyM = uncertainty
        if let coordinate = state.coordinate { history.append((timestamp, coordinate)) }
        history.removeAll { timestamp.timeIntervalSince($0.0) > configuration.observationFreshness + 1 }
    }
    @discardableResult public mutating func correct(_ observation: GPSObservation, monotonicTime: Double, timestamp: Date, mode: TravelMode, compass: CompassObservation?) -> Bool {
        guard lastCheck == nil || monotonicTime - lastCheck! >= configuration.correctionInterval else { return false }
        lastCheck = monotonicTime
        guard let observedAt = observation.observedAt, observedAt != lastObservation,
              lastObservation.map({ observedAt > $0 }) ?? true,
              (0...configuration.observationFreshness).contains(timestamp.timeIntervalSince(observedAt)),
              let coordinate = observation.coordinate, coordinate.isValid,
              let accuracy = observation.horizontalAccuracyM, accuracy.isFinite, (0...65).contains(accuracy) else { return false }
        lastObservation = observedAt
        let speedLimit: Double = mode == .flight ? 450 : mode == .driving ? 85 : mode == .cycling ? 30 : 12
        if let previous = lastAccepted, let origin = previous.coordinate, let previousDate = previous.observedAt {
            let dt = observedAt.timeIntervalSince(previousDate)
            guard dt > 0, origin.distance(to: coordinate) <= speedLimit * dt + accuracy + (previous.horizontalAccuracyM ?? 0) else { return false }
        }
        // Compare a prediction at the observation epoch, not an old fix against the current position.
        let prediction = history.min { abs($0.0.timeIntervalSince(observedAt)) < abs($1.0.timeIntervalSince(observedAt)) }
        if state.coordinate != nil {
            guard let prediction, abs(prediction.0.timeIntervalSince(observedAt)) <= 0.25 else { return false }
            let residual = prediction.1.distance(to: coordinate)
            let gate = max(10, 3 * hypot(accuracy, state.horizontalUncertaintyM ?? 0))
            guard residual <= gate else { return false }
            if residual > max(3, accuracy) {
                let current = state.coordinate!
                var longitude = coordinate.longitude - prediction.1.longitude
                if longitude > 180 { longitude -= 360 }; if longitude < -180 { longitude += 360 }
                let gain = min(0.85, max(0.15, (state.horizontalUncertaintyM ?? accuracy) / max(1, accuracy + (state.horizontalUncertaintyM ?? accuracy))))
                state.coordinate = Coordinate(current.latitude + (coordinate.latitude - prediction.1.latitude) * gain,
                                              Self.wrap(current.longitude + longitude * gain))
            }
        } else { state.coordinate = coordinate }
        // A speed scalar cannot initialize direction. At rest zero velocity is known; otherwise course is required.
        if let speed = observation.speedMps, speed.isFinite, speed >= 0, speed <= speedLimit {
            if speed < 0.2 { state.velocityENU = VectorENU(east: 0, north: 0, up: 0) }
            else if let course = observation.courseDeg, (0..<360).contains(course) {
                state.velocityENU = VectorENU(east: sin(course * .pi / 180) * speed, north: cos(course * .pi / 180) * speed, up: 0)
            }
        }
        guard let velocity = state.velocityENU else { state.coordinate = nil; state.status = .uninitialized; return false }
        // Never use a scalar speed and the phone's heading to invent a velocity vector.
        state.speedMps = velocity.horizontalSpeed
        if let altitude = observation.altitudeM, let verticalAccuracy = observation.verticalAccuracyM, verticalAccuracy >= 0 { state.altitudeM = altitude }
        let direction = Self.bearing(previous: nil, compass: compass, at: timestamp, minimumSpeed: configuration.minimumBearingSpeed)
        if state.bearingDeg == nil { state.bearingDeg = direction.0; state.bearingSource = direction.1; state.bearingReference = direction.2 }
        state.status = .corrected; state.lastCorrectionAt = observedAt; state.predictionAgeSeconds = timestamp.timeIntervalSince(observedAt)
        state.horizontalUncertaintyM = accuracy; correctedTime = monotonicTime - timestamp.timeIntervalSince(observedAt)
        lastAccepted = observation
        history.append((timestamp, state.coordinate!)); return true
    }
    private static func wrap(_ longitude: Double) -> Double { (longitude + 540).truncatingRemainder(dividingBy: 360) - 180 }
    private static func offset(_ coordinate: Coordinate, east: Double, north: Double) -> Coordinate? {
        guard abs(coordinate.latitude) < 89 else { return nil }
        let latitude = coordinate.latitude + north / 111_195
        let longitude = wrap(coordinate.longitude + east / (111_195 * cos(coordinate.latitude * .pi / 180)))
        let result = Coordinate(latitude, longitude); return result.isValid ? result : nil
    }
}
