import Foundation

/// All calls must be serialized by the owner (Recorder uses the main actor).
public final class TrackStore {
    public let directory: URL
    public struct LoadResult { public var sessions: [TrackSession]; public var warnings: [String] }
    struct LegacyEvent: Codable { var metadata: TrackSession?; var point: TrackPoint?; var motion: MotionSample?; var distance: Double? }
    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    private func url(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString).appendingPathExtension("jsonl") }
    public func saveMetadata(_ session: TrackSession) throws {
        try TrackDocument(metadata: TrackMetadata(session: session), samples: []).validate()
        let file = url(session.id)
        if !FileManager.default.fileExists(atPath: file.path) {
            try writeNew(TrackDocument(session: session), to: file)
            return
        }
        let reader = try FileHandle(forReadingFrom: file)
        defer { try? reader.close() }
        // Read a bounded header; preserve the remaining bytes without decoding a large route.
        var header = Data(), remainder = Data()
        while let block = try reader.read(upToCount: 64 * 1024), !block.isEmpty {
            if let newline = block.firstIndex(of: 10) {
                header.append(block[..<newline]); remainder = Data(block[block.index(after: newline)...]); break
            }
            header.append(block)
            guard header.count <= TrackCodec.maximumBytes else { throw TrackFileError.invalid("记录首部过大") }
        }
        if (try? TrackCodec.decoder().decode(TrackMetadata.self, from: header)) == nil {
            let backup = file.appendingPathExtension("legacy-backup")
            if !FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.copyItem(at: file, to: backup) }
            try writeNew(TrackDocument(session: session), to: file)
            return
        }
        try atomicWrite(file) { writer in
            var data = try TrackCodec.encoder().encode(TrackMetadata(session: session)); data.append(10)
            try writer.write(contentsOf: data); try writer.write(contentsOf: remainder)
            while let block = try reader.read(upToCount: 256 * 1024), !block.isEmpty { try writer.write(contentsOf: block) }
        }
    }
    public func appendSample(_ sample: NavigationSample, id: UUID) throws {
        let file = url(id)
        let handle = try FileHandle(forUpdating: file)
        defer { try? handle.close() }
        let length = try handle.seekToEnd()
        if length > 0 {
            try handle.seek(toOffset: length - 1)
            let last = try handle.read(upToCount: 1); try handle.seekToEnd()
            if last?.last != 10 { try handle.write(contentsOf: Data([10])) }
        }
        var data = try TrackCodec.encoder().encode(sample); data.append(10)
        try handle.write(contentsOf: data); try handle.synchronize()
    }
    public func appendPoint(_ point: TrackPoint, session: TrackSession) throws {
        var sample = NavigationSample(sequence: session.points.count, segmentId: point.segment, timestamp: point.timestamp,
                                     gps: GPSObservation(point: point), id: point.id)
        sample.cumulativeDistanceM = session.distance
        try appendSample(sample, id: session.id)
    }
    public func delete(_ id: UUID) throws { try FileManager.default.removeItem(at: url(id)) }
    public func importDocuments(_ documents: [TrackDocument]) throws -> [TrackSession] {
        // Stage every selected track first, then roll back new files if any rename fails.
        var pending: [(URL, URL, TrackSession)] = [], installed: [URL] = []
        do {
            for document in documents {
                var value = document
                value.metadata.provenance = TrackProvenance(sourceID: document.metadata.provenance?.sourceID ?? document.metadata.sessionId,
                    fingerprint: document.metadata.provenance?.fingerprint, originalState: document.metadata.provenance?.originalState ?? document.metadata.state)
                value.metadata.sessionId = UUID(); value.metadata.state = .finished; value.metadata.intervalStartedAt = nil
                let destination = url(value.metadata.sessionId)
                let staged = directory.appendingPathComponent(".import-\(UUID().uuidString)")
                pending.append((staged, destination, value.session()))
                try writeNew(value, to: staged)
            }
            for (staged, destination, _) in pending {
                try FileManager.default.moveItem(at: staged, to: destination); installed.append(destination)
            }
            return pending.map { $0.2 }
        } catch {
            var cleanupFailed = false
            for file in installed + pending.map({ $0.0 }) where FileManager.default.fileExists(atPath: file.path) {
                do { try FileManager.default.removeItem(at: file) } catch { cleanupFailed = true }
            }
            if cleanupFailed { throw TrackFileError.invalid("导入失败，部分文件无法回滚；请重新打开日志核对。原始文件未修改。") }
            throw error
        }
    }
    private func writeNew(_ document: TrackDocument, to file: URL) throws {
        try document.validate()
        try atomicWrite(file) { handle in
            let encoder = TrackCodec.encoder()
            var header = try encoder.encode(document.metadata); header.append(10); try handle.write(contentsOf: header)
            for sample in document.samples {
                var line = try encoder.encode(sample); line.append(10); try handle.write(contentsOf: line)
            }
        }
    }
    private func atomicWrite(_ file: URL, write: (FileHandle) throws -> Void) throws {
        let temporary = directory.appendingPathComponent(".write-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        do {
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: temporary.path)
            #endif
            let writer = try FileHandle(forWritingTo: temporary)
            do { try write(writer); try writer.synchronize(); try writer.close() }
            catch { try? writer.close(); throw error }
            if FileManager.default.fileExists(atPath: file.path) {
                _ = try FileManager.default.replaceItemAt(file, withItemAt: temporary)
            } else { try FileManager.default.moveItem(at: temporary, to: file) }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
    public func load() throws -> LoadResult {
        var sessions: [TrackSession] = [], warnings: [String] = []
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "jsonl" }) {
            do {
                let bytes = try Data(contentsOf: file)
                let result = try TrackImport.decodeJSONL(bytes, recoverTail: true)
                guard var session = result.documents.first?.session() else { throw TrackFileError.invalid("缺少会话首部") }
                guard file.deletingPathExtension().lastPathComponent == session.id.uuidString else { throw TrackFileError.invalid("文件名与会话 ID 不一致") }
                if let length = result.recoveredLength {
                    let backup = file.appendingPathExtension("\(UUID().uuidString).recovery-backup")
                    try FileManager.default.copyItem(at: file, to: backup)
                    try bytes.prefix(length).write(to: file, options: .atomic)
                    warnings.append(contentsOf: result.warnings)
                }
                if session.state == .recording {
                    let persisted = (session.navigationSamples ?? []).compactMap(\.timestamp).last ?? session.startedAt
                    session.pause(at: max(persisted ?? .distantPast, session.intervalStartedAt ?? .distantPast))
                    try saveMetadata(session)
                    warnings.append("上次记录已恢复为暂停状态。继续时会开启新的轨迹段。")
                }
                sessions.append(session)
            } catch { warnings.append("无法读取 \(file.lastPathComponent)：\(error.localizedDescription)。原文件已保留。") }
        }
        return LoadResult(sessions: sessions.sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }, warnings: warnings)
    }
    public func writeExport(_ session: TrackSession, gpx: Bool, to directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("Altiscope-\(session.id.uuidString.prefix(8))").appendingPathExtension(gpx ? "gpx" : "json")
        let document = TrackDocument(session: session); try document.validate()
        if gpx {
            let strings = [session.title, session.notes]
            guard strings.allSatisfy({ $0.unicodeScalars.allSatisfy { $0.value >= 32 || [9,10,13].contains($0.value) } }) else { throw TrackFileError.invalid("笔记含 GPX 不支持的控制字符，请使用 JSON 导出") }
        }
        let data = try gpx ? Data(TrackExport.gpx(session).utf8) : TrackCodec.json(document)
        try data.write(to: file, options: .atomic); return file
    }
}
