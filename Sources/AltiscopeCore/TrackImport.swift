import Foundation
import CryptoKit
import CoreFoundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct TrackImportResult: Sendable {
    public var documents: [TrackDocument]
    public var warnings: [String] = []
    public var recoveredLength: Int?
}
public enum TrackImport {
    public static func read(_ data: Data, extension ext: String, filename: String) throws -> TrackImportResult {
        guard data.count <= TrackCodec.maximumBytes else { throw TrackFileError.invalid("文件超过 64 MiB 导入上限") }
        try Task.checkCancellation()
        var result: TrackImportResult
        switch ext.lowercased() {
        case "gpx": result = try GPXCodec.read(data)
        case "jsonl": result = try decodeJSONL(data, recoverTail: true)
        case "json":
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if object?["metadata"] != nil {
                let document = try TrackCodec.decoder().decode(TrackDocument.self, from: data)
                try document.validate(); result = TrackImportResult(documents: [document])
            } else {
                let document = TrackDocument(session: try legacyDecoder().decode(TrackSession.self, from: data))
                try document.validate(); result = TrackImportResult(documents: [document])
            }
        default: throw TrackFileError.invalid("仅支持 GPX、JSON 和 JSONL")
        }
        let fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        for index in result.documents.indices {
            var metadata = result.documents[index].metadata
            if metadata.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { metadata.name = filename }
            metadata.provenance = TrackProvenance(sourceID: metadata.provenance?.sourceID ?? metadata.sessionId,
                fingerprint: fingerprint + ":\(index)", originalState: metadata.provenance?.originalState ?? metadata.state)
            result.documents[index].metadata = metadata
            if result.documents[index].samples.contains(where: { $0.timestamp == nil }) {
                result.warnings.append("“\(metadata.name)”含未计时采样；缺失时间不参与时长和时间曲线。")
            }
            try result.documents[index].validate()
        }
        return result
    }
    static func legacyDecoder() -> JSONDecoder {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970; return decoder
    }
    public static func decodeJSONL(_ data: Data, recoverTail: Bool) throws -> TrackImportResult {
        let lines = data.split(separator: 10, omittingEmptySubsequences: false)
        let meaningful = lines.indices.filter { !lines[$0].isEmpty }
        guard let first = meaningful.first else { throw TrackFileError.invalid("文件为空") }
        let firstObject = try JSONSerialization.jsonObject(with: Data(lines[first])) as? [String: Any]
        let versioned = firstObject?["format"] != nil || firstObject?["recordType"] != nil
        var metadata: TrackMetadata?, samples: [NavigationSample] = [], legacy: TrackSession?
        var offset = 0, recovered: Int?, warnings: [String] = []
        let decoder = TrackCodec.decoder(), oldDecoder = legacyDecoder()
        for index in lines.indices {
            try Task.checkCancellation()
            let line = lines[index]
            if line.isEmpty { offset += 1; continue }
            // Only syntactically incomplete final JSON is recoverable. Semantic errors remain errors.
            do { _ = try JSONSerialization.jsonObject(with: Data(line)) }
            catch {
                if recoverTail, index == meaningful.last, data.last != 10, metadata != nil || legacy != nil {
                    recovered = min(offset, data.count)
                    warnings.append("第 \(index + 1) 行写入未完成；仅恢复前 \(index) 行，原文件/备份保留。")
                    break
                }
                throw TrackFileError.invalid("第 \(index + 1) 行损坏，停止读取；未跳过中间数据。")
            }
            do {
                if versioned {
                    if index == first { metadata = try decoder.decode(TrackMetadata.self, from: Data(line)) }
                    else { samples.append(try decoder.decode(NavigationSample.self, from: Data(line))) }
                } else {
                    let event = try oldDecoder.decode(TrackStore.LegacyEvent.self, from: Data(line))
                    guard event.metadata != nil || event.point != nil || event.motion != nil else { throw TrackFileError.invalid("无法识别旧事件") }
                    if var value = event.metadata {
                        value.points = legacy?.points ?? value.points; value.motion = legacy?.motion ?? value.motion; legacy = value
                    }
                    guard legacy != nil else { throw TrackFileError.invalid("采样之前缺少会话元数据") }
                    if let point = event.point { legacy?.points.append(point); legacy?.segment = point.segment }
                    if let motion = event.motion { legacy?.motion.append(motion) }
                    if let distance = event.distance { legacy?.distance = distance }
                }
            } catch { throw TrackFileError.invalid("第 \(index + 1) 行：\(error.localizedDescription)") }
            offset += line.count + 1
            guard samples.count <= TrackCodec.maximumSamples else { throw TrackFileError.invalid("采样数超出上限") }
        }
        let document: TrackDocument
        if let metadata { document = TrackDocument(metadata: metadata, samples: samples) }
        else if let legacy { document = TrackDocument(session: legacy) }
        else { throw TrackFileError.invalid("缺少记录首部") }
        try document.validate()
        return TrackImportResult(documents: [document], warnings: warnings, recoveredLength: recovered)
    }
}

public enum TrackExport {
    public static func gpx(_ session: TrackSession) -> String { GPXCodec.write(TrackDocument(session: session)) }
}

enum GPXCodec {
    static let namespace = "urn:altiscope:track:1"
    static let gpxNamespace = "http://www.topografix.com/GPX/1/1"
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;").replacingOccurrences(of: "\r", with: "&#13;")
    }
    // Typed XML mirrors the JSON tree, including nulls and arrays, without opaque encoded blobs.
    static func xml(_ key: String, _ value: Any) -> String {
        if value is NSNull { return "<alt:\(key) missing=\"true\"/>" }
        if let object = value as? [String: Any] {
            return "<alt:\(key) type=\"object\">" + object.keys.sorted().map { xml($0, object[$0]!) }.joined() + "</alt:\(key)>"
        }
        if let array = value as? [Any] { return "<alt:\(key) type=\"array\">" + array.map { xml("item", $0) }.joined() + "</alt:\(key)>" }
        if let number = value as? NSNumber {
            let boolean = CFGetTypeID(number) == CFBooleanGetTypeID()
            return "<alt:\(key) type=\"\(boolean ? "boolean" : "number")\">\(boolean ? (number.boolValue ? "true" : "false") : number.stringValue)</alt:\(key)>"
        }
        return "<alt:\(key) type=\"string\">\(escape(value as? String ?? ""))</alt:\(key)>"
    }
    static func object<T: Encodable>(_ value: T) -> Any {
        // All values passed here come from a validated document before file export.
        do { return try JSONSerialization.jsonObject(with: TrackCodec.encoder().encode(value)) }
        catch { preconditionFailure("Invalid export model: \(error)") }
    }
    static func write(_ document: TrackDocument) -> String {
        let m = document.metadata
        var text = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<gpx version=\"1.1\" creator=\"Altiscope\" xmlns=\"\(gpxNamespace)\" xmlns:alt=\"\(namespace)\"><trk>"
        text += "<name>\(escape(m.name))</name><desc>\(escape(m.notes))</desc>"
        if let mode = m.travelMode { text += "<type>\(mode.rawValue)</type>" }
        text += "<extensions>" + xml("metadata", object(m)) + "<alt:unpositionedSamples>"
        for sample in document.samples where sample.displayCoordinate == nil { text += xml("sample", object(sample)) }
        text += "</alt:unpositionedSamples></extensions>"
        var currentSegment: Int?
        for sample in document.samples {
            guard let coordinate = sample.displayCoordinate else { if currentSegment != nil { text += "</trkseg>"; currentSegment = nil }; continue }
            if currentSegment != sample.segmentId {
                if currentSegment != nil { text += "</trkseg>" }
                text += "<trkseg>"; currentSegment = sample.segmentId
            }
            text += "<trkpt lat=\"\(coordinate.latitude)\" lon=\"\(coordinate.longitude)\">"
            if let altitude = sample.displayAltitude { text += "<ele>\(altitude)</ele>" }
            if let timestamp = sample.timestamp { text += "<time>\(TrackCodec.dateString(timestamp))</time>" }
            text += "<extensions><alt:positionSource>\(sample.usesInertial ? "inertial" : "observation")</alt:positionSource>" + xml("sample", object(sample)) + "</extensions></trkpt>"
        }
        if currentSegment != nil { text += "</trkseg>" }
        return text + "</trk></gpx>"
    }
    static func read(_ data: Data) throws -> TrackImportResult {
        // Reject DTDs before parsing, including UTF-16/32 input, so external subsets are never consulted.
        for encoding: String.Encoding in [.utf8, .utf16, .utf16BigEndian, .utf16LittleEndian, .utf32, .utf32BigEndian, .utf32LittleEndian] {
            if let text = String(data: data, encoding: encoding), text.uppercased().contains("<!DOCTYPE") { throw TrackFileError.invalid("GPX 不允许 DTD 或实体声明") }
        }
        let tree = SafeXMLTree(); let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true; parser.shouldResolveExternalEntities = false; parser.delegate = tree
        guard parser.parse(), let root = tree.root, tree.failure == nil else {
            throw tree.failure ?? TrackFileError.invalid("GPX 第 \(parser.lineNumber) 行：\(parser.parserError?.localizedDescription ?? "XML 无效")")
        }
        guard root.name == "gpx", root.namespace == gpxNamespace, root.attributes["version"] == "1.1" else { throw TrackFileError.invalid("仅支持 GPX 1.1") }
        let tracks = root.children.filter { ["trk", "rte"].contains($0.name) && $0.namespace == gpxNamespace }
        guard !tracks.isEmpty else { throw TrackFileError.invalid("文件没有轨迹或路径；独立航点不作为旅程导入") }
        var documents: [TrackDocument] = []
        for track in tracks {
            try Task.checkCancellation()
            let extensionNode = track.child("extensions")
            let fullMetadata = extensionNode?.child("metadata", namespace: namespace)
            var samples: [NavigationSample] = []
            let groups = track.name == "rte" ? [track] : track.children.filter { $0.name == "trkseg" && $0.namespace == gpxNamespace }
            for (segment, group) in groups.enumerated() {
                var extensionSegment: Int?
                for point in group.children.filter({ ["trkpt", "rtept"].contains($0.name) && $0.namespace == gpxNamespace }) {
                    guard let latitude = point.attributes["lat"].flatMap(Double.init), let longitude = point.attributes["lon"].flatMap(Double.init), Coordinate(latitude, longitude).isValid else { throw TrackFileError.invalid("GPX 坐标无效") }
                    let coordinate = Coordinate(latitude, longitude)
                    let altitude = try point.child("ele").map { node -> Double in
                        guard let value = Double(node.text), value.isFinite else { throw TrackFileError.invalid("GPX 高度无效") }; return value
                    }
                    let time = try point.child("time").map { node -> Date in
                        guard let value = TrackCodec.date(node.text) else { throw TrackFileError.invalid("GPX 时间无效") }; return value
                    }
                    if let full = point.child("extensions")?.child("sample", namespace: namespace) {
                        guard fullMetadata != nil else { throw TrackFileError.invalid("详细采样缺少 Altiscope 元数据") }
                        let sample = try TrackCodec.decoder().decode(NavigationSample.self, from: JSONSerialization.data(withJSONObject: full.json()))
                        guard point.child("extensions")?.child("positionSource", namespace: namespace)?.text == (sample.usesInertial ? "inertial" : "observation"),
                              let expected = sample.displayCoordinate, expected.distance(to: coordinate) < 0.01,
                              sample.displayAltitude == altitude, sample.timestamp == time else { throw TrackFileError.invalid("GPX 标准轨迹点与详细扩展不一致") }
                        if let extensionSegment, extensionSegment != sample.segmentId { throw TrackFileError.invalid("GPX 分段与扩展不一致") }
                        extensionSegment = sample.segmentId
                        samples.append(sample)
                    } else {
                        guard fullMetadata == nil else { throw TrackFileError.invalid("Altiscope 轨迹缺少详细采样扩展") }
                        var gps = GPSObservation(); gps.coordinate = coordinate; gps.altitudeM = altitude; gps.observedAt = time; gps.source = "external_gpx_unknown"
                        samples.append(NavigationSample(sequence: samples.count + 1, segmentId: segment, timestamp: time, gps: gps))
                    }
                }
            }
            let metadata: TrackMetadata
            if let fullMetadata {
                metadata = try TrackCodec.decoder().decode(TrackMetadata.self, from: JSONSerialization.data(withJSONObject: fullMetadata.json()))
                for node in extensionNode?.child("unpositionedSamples", namespace: namespace)?.children ?? [] {
                    guard node.namespace == namespace, node.name == "sample" else { throw TrackFileError.invalid("未知无坐标采样") }
                    let sample = try TrackCodec.decoder().decode(NavigationSample.self, from: JSONSerialization.data(withJSONObject: node.json()))
                    guard sample.displayCoordinate == nil else { throw TrackFileError.invalid("无坐标扩展中存在定位点") }; samples.append(sample)
                }
                guard metadata.name == (track.child("name")?.text ?? ""), metadata.notes == (track.child("desc")?.text ?? ""), metadata.travelMode?.rawValue == track.child("type")?.text else { throw TrackFileError.invalid("GPX 名称、笔记或类型与扩展不一致") }
                samples.sort { $0.sequence < $1.sequence }
            } else {
                guard !samples.isEmpty else { throw TrackFileError.invalid("GPX 路径没有轨迹点") }
                var session = TrackSession(title: track.child("name")?.text ?? "", mode: .walking)
                session.notes = track.child("desc")?.text ?? ""; session.state = .finished; session.intervalStartedAt = nil
                session.startedAt = samples.compactMap(\.timestamp).min(); session.endedAt = samples.compactMap(\.timestamp).max()
                session.durationKnown = samples.allSatisfy { $0.timestamp != nil }
                session.activeSeconds = zip(samples, samples.dropFirst()).reduce(0) { total, pair in
                    guard pair.0.segmentId == pair.1.segmentId, let a = pair.0.timestamp, let b = pair.1.timestamp else { return total }
                    return total + max(0, b.timeIntervalSince(a))
                }
                session.altitudeReference = "unknown"; session.distance = TrackDocument.distance(samples)
                var value = TrackMetadata(session: session); value.travelMode = track.child("type").flatMap { TravelMode(rawValue: $0.text) }; metadata = value
            }
            let document = TrackDocument(metadata: metadata, samples: samples); try document.validate(); documents.append(document)
        }
        return TrackImportResult(documents: documents)
    }
}

private final class XMLNode {
    let name: String; let namespace: String; let attributes: [String: String]
    var text = ""; var children: [XMLNode] = []
    init(_ name: String, _ namespace: String, _ attributes: [String: String]) { self.name = name; self.namespace = namespace; self.attributes = attributes }
    func child(_ name: String, namespace: String = GPXCodec.gpxNamespace) -> XMLNode? { children.first { $0.name == name && $0.namespace == namespace } }
    func json() throws -> Any {
        if attributes["missing"] == "true" { return NSNull() }
        switch attributes["type"] {
        case "object":
            var result: [String: Any] = [:]
            for child in children {
                guard child.namespace == GPXCodec.namespace, result[child.name] == nil else { throw TrackFileError.invalid("扩展字段重复或命名空间无效") }
                result[child.name] = try child.json()
            }; return result
        case "array": return try children.map { try $0.json() }
        case "boolean": guard ["true", "false"].contains(text) else { throw TrackFileError.invalid("布尔值无效") }; return text == "true"
        case "number": guard let value = Double(text), value.isFinite else { throw TrackFileError.invalid("扩展数值无效") }; return value
        case "string": return text
        default: throw TrackFileError.invalid("未知扩展字段类型")
        }
    }
}
private final class SafeXMLTree: NSObject, XMLParserDelegate {
    var root: XMLNode?, stack: [XMLNode] = [], failure: Error?, count = 0
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        count += 1
        guard stack.count < 32, count <= 2_000_000, !Task.isCancelled else { failure = TrackFileError.invalid("XML 超过资源限制或操作已取消"); parser.abortParsing(); return }
        let node = XMLNode(elementName, namespaceURI ?? "", attributes)
        if let parent = stack.last { parent.children.append(node) } else { root = node }; stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) { _ = stack.popLast() }
    func reject(_ parser: XMLParser) { failure = TrackFileError.invalid("GPX 不允许实体声明或外部资源"); parser.abortParsing() }
    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) { reject(parser) }
    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) { reject(parser) }
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { reject(parser); return nil }
}
