import Foundation

/// Append-only event files keep each accepted fix durable without rewriting a growing route.
/// This type is used on one serial queue (the app's main actor).
public final class TrackStore {
    public let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    public struct LoadResult { public var sessions: [TrackSession]; public var warnings: [String] }
    private struct Event: Codable { var metadata: TrackSession?; var point: TrackPoint?; var motion: MotionSample?; var distance: Double? }
    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        encoder.dateEncodingStrategy = .iso8601; decoder.dateDecodingStrategy = .iso8601
        // Preserve sub-second timing for samples and duration calculations.
        encoder.dateEncodingStrategy = .millisecondsSince1970; decoder.dateDecodingStrategy = .millisecondsSince1970
    }
    private func url(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString).appendingPathExtension("jsonl") }
    public func saveMetadata(_ session: TrackSession) throws {
        var metadata = session; metadata.points = []; metadata.motion = []
        try append(Event(metadata: metadata), id: session.id)
    }
    public func appendPoint(_ point: TrackPoint, session: TrackSession) throws {
        try append(Event(point: point, distance: session.distance), id: session.id)
    }
    public func appendMotion(_ motion: MotionSample, id: UUID) throws { try append(Event(motion: motion), id: id) }
    private func append(_ event: Event, id: UUID) throws {
        let file = url(id)
        if !FileManager.default.fileExists(atPath: file.path) {
            guard FileManager.default.createFile(atPath: file.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
            #endif
        }
        let handle = try FileHandle(forUpdating: file)
        defer { try? handle.close() }
        let length = try handle.seekToEnd()
        if length > 0 {
            try handle.seek(toOffset: length - 1)
            let last = try handle.read(upToCount: 1)
            try handle.seekToEnd()
            if last?.last != 0x0a { try handle.write(contentsOf: Data([0x0a])) }
        }
        var data = try encoder.encode(event); data.append(0x0a)
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }
    public func load() throws -> LoadResult {
        var sessions: [TrackSession] = [], warnings: [String] = []
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "jsonl" }) {
            do {
                let bytes = try Data(contentsOf: file)
                var session: TrackSession?
                var validLength = 0
                let lines = bytes.split(separator: 0x0a, omittingEmptySubsequences: false)
                for (index, line) in lines.enumerated() {
                    if line.isEmpty { continue }
                    do {
                        let event = try decoder.decode(Event.self, from: Data(line))
                        if var metadata = event.metadata {
                            metadata.points = session?.points ?? []; metadata.motion = session?.motion ?? []
                            session = metadata
                        }
                        if let point = event.point { session?.points.append(point); session?.segment = point.segment }
                        if let distance = event.distance { session?.distance = distance }
                        if let motion = event.motion { session?.motion.append(motion) }
                        validLength += line.count + 1
                    } catch {
                        if index >= lines.count - 2 {
                            // Preserve original data for diagnostics, truncate only an incomplete final event.
                            let backup = file.appendingPathExtension("recovery-backup")
                            if !FileManager.default.fileExists(atPath: backup.path) { try bytes.write(to: backup) }
                            try bytes.prefix(min(validLength, bytes.count)).write(to: file, options: .atomic)
                            warnings.append("恢复了一份末尾写入中断的记录。")
                            break
                        }
                        throw error
                    }
                }
                if var value = session {
                    if value.state == .recording {
                        let lastPersisted = max(value.points.last?.timestamp ?? value.startedAt, value.motion.last?.timestamp ?? value.startedAt)
                        value.pause(at: max(lastPersisted, value.intervalStartedAt ?? value.startedAt))
                        try saveMetadata(value)
                        warnings.append("上次记录已恢复为暂停状态，可继续记录。")
                    }
                    sessions.append(value)
                }
            } catch { warnings.append("有一份记录无法读取，原文件已保留：\(file.lastPathComponent)") }
        }
        return LoadResult(sessions: sessions.sorted { $0.startedAt > $1.startedAt }, warnings: warnings)
    }
    public func writeExport(_ session: TrackSession, gpx: Bool, to directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("Altiscope-\(session.id.uuidString.prefix(8))").appendingPathExtension(gpx ? "gpx" : "json")
        let data = try gpx ? Data(TrackExport.gpx(session).utf8) : encoder.encode(session)
        try data.write(to: file, options: .atomic)
        return file
    }
}
