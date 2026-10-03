import SwiftUI
import UniformTypeIdentifiers

struct JournalView: View {
    @EnvironmentObject var recorder: Recorder
    let openMap: () -> Void
    @State private var query = ""
    @State private var managing: TrackSession?
    @State private var picking = false
    @State private var importPreview: ImportPreview?
    @State private var importTask: Task<TrackImportResult, Error>?
    @State private var importID: UUID?
    @State private var importing = false
    @State private var error: String?
    struct ImportPreview: Identifiable { let id = UUID(); var result: TrackImportResult }
    var records: [TrackSession] {
        var records = recorder.sessions
        if let active = recorder.active { records.removeAll { $0.id == active.id }; records.insert(active, at: 0) }
        return records.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.notes.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("YOUR LOGBOOK").smallLabel()
                HStack {
                    Text("旅程日志").font(.title.bold()); Spacer()
                    Button { picking = true } label: { Image(systemName: "square.and.arrow.down").frame(width: 44, height: 44) }.accessibilityLabel("导入轨迹").disabled(importing)
                }
                HStack(spacing: 20) {
                    Metric(title: "累计里程", value: Display.distance(records.reduce(0) { $0 + $1.distance }), unit: "km")
                    Metric(title: "已知记录时长", value: Display.number(records.filter { $0.durationKnown != false }.reduce(0) { $0 + $1.duration(at: recorder.now) } / 3600, decimals: 1), unit: "h")
                }.panel()
                HStack { Image(systemName: "magnifyingglass"); TextField("搜索名称", text: $query) }.foregroundStyle(Theme.secondary).padding(14).background(Theme.panel, in: RoundedRectangle(cornerRadius: 13))
                if importing {
                    HStack { ProgressView(); Text("正在检查文件"); Spacer(); Button("取消") { importTask?.cancel(); importTask = nil; importID = nil; importing = false } }.panel()
                }
                if records.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").font(.largeTitle).foregroundStyle(Theme.accent)
                        Text(query.isEmpty ? "第一段旅程，等你出发。" : "没有匹配的记录")
                        Button("查看示例") { recorder.showDemo(); openMap() }
                    }.frame(maxWidth: .infinity).padding(.vertical, 45)
                }
                ForEach(records) { session in
                    HStack(spacing: 8) {
                        Button { recorder.select(session); openMap() } label: {
                            HStack(spacing: 14) {
                                Image(systemName: session.mode.symbol).font(.title2).foregroundStyle(Theme.accent).frame(width: 35)
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(session.title).font(.headline).lineLimit(1)
                                    Text(session.startedAt?.formatted(date: .abbreviated, time: .shortened) ?? "时间未知 · 按文件顺序").font(.caption2).foregroundStyle(Theme.secondary)
                                    Text("\(Display.distance(session.distance)) km · \(session.durationKnown == false ? "时长未知" : Display.duration(session.duration(at: recorder.now)))").font(.caption.monospaced()).foregroundStyle(Theme.accent)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Button {
                            if session.state == .finished && session.id != recorder.active?.id { managing = session }
                            else { error = "请先结束当前旅程，再修改类型或删除。" }
                        } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }.accessibilityLabel("管理 \(session.title)")
                    }.panel()
                }
            }.padding(20)
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            do { if let url = try result.get().first { beginImport(url) } } catch { self.error = error.localizedDescription }
        }
        .sheet(item: $managing) { session in ManageRecordView(session: session) }
        .sheet(item: $importPreview) { preview in ImportPreviewView(result: preview.result) }
        .alert("日志", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("知道了", role: .cancel) {} } message: { Text(error ?? "") }
        .onDisappear { importTask?.cancel() }
    }
    private func beginImport(_ url: URL) {
        importTask?.cancel()
        let identifier = UUID(); importID = identifier
        importing = true
        let task = Task.detached(priority: .userInitiated) { () throws -> TrackImportResult in
            let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= TrackCodec.maximumBytes else { throw TrackFileError.invalid("文件超过 64 MiB 上限") }
            try Task.checkCancellation()
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            return try TrackImport.read(data, extension: url.pathExtension, filename: url.deletingPathExtension().lastPathComponent)
        }
        importTask = task
        Task { @MainActor in
            do { let result = try await task.value; if importID == identifier && !task.isCancelled { importPreview = ImportPreview(result: result) } }
            catch { if importID == identifier && !task.isCancelled { self.error = error.localizedDescription } }
            if importID == identifier { importing = false; importTask = nil; importID = nil }
        }
    }
}
struct ManageRecordView: View {
    @EnvironmentObject var recorder: Recorder
    @Environment(\.dismiss) private var dismiss
    let session: TrackSession
    @State private var name: String
    @State private var notes: String
    @State private var mode: TravelMode
    @State private var confirmDelete = false
    @State private var error: String?
    init(session: TrackSession) { self.session = session; _name = State(initialValue: session.title); _notes = State(initialValue: session.notes); _mode = State(initialValue: session.mode) }
    var body: some View {
        NavigationStack {
            Form {
                Section("名称") { TextField("名称", text: $name) }
                Section("类型") { Picker("出行方式", selection: $mode) { ForEach(TravelMode.allCases, id: \.self) { Text($0.title).tag($0) } } }
                Section("笔记") { TextEditor(text: $notes).frame(minHeight: 120) }
                Section { Text("修改类型仅更新分类，保留原始采样与历史统计。").font(.footnote); Button("删除这条轨迹", role: .destructive) { confirmDelete = true } }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("管理轨迹").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") {
                        if recorder.manage(session, name: name, mode: mode, notes: notes) { dismiss() }
                        else { error = recorder.message; recorder.message = nil }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
                .alert("删除“\(session.title)”？", isPresented: $confirmDelete) {
                    Button("取消", role: .cancel) {}
                    Button("删除", role: .destructive) {
                        if recorder.delete(session) { dismiss() } else { error = recorder.message; recorder.message = nil }
                    }
                } message: { Text("删除本机这一条记录，其他旅程不受影响。") }
        }
    }
}
struct ImportPreviewView: View {
    @EnvironmentObject var recorder: Recorder
    @Environment(\.dismiss) private var dismiss
    @State private var documents: [TrackDocument]
    @State private var chosen: Set<Int> = []
    @State private var error: String?
    let warnings: [String]
    init(result: TrackImportResult) { _documents = State(initialValue: result.documents); warnings = result.warnings }
    var ready: Bool { !chosen.isEmpty && chosen.allSatisfy { documents[$0].metadata.travelMode != nil } }
    var body: some View {
        NavigationStack {
            Form {
                ForEach(warnings, id: \.self) { Text($0).foregroundStyle(.orange).font(.footnote) }
                ForEach(documents.indices, id: \.self) { index in
                    let document = documents[index]
                    Section(document.metadata.name) {
                        Toggle(recorder.isDuplicate(document) ? "发现重复 · 作为独立副本导入" : "导入此轨迹", isOn: Binding(get: { chosen.contains(index) }, set: { if $0 { chosen.insert(index) } else { chosen.remove(index) } }))
                        Text("\(document.samples.count) 次采样 · \(document.samples.filter { $0.displayCoordinate != nil }.count) 个轨迹点 · \(Set(document.samples.map(\.segmentId)).count) 段")
                        Text("\(document.metadata.startedAt?.formatted() ?? "开始时间未知") → \(document.metadata.endedAt?.formatted() ?? "结束时间未知")").font(.footnote)
                        Picker("记录类型", selection: $documents[index].metadata.travelMode) {
                            Text("请选择类型").tag(TravelMode?.none)
                            ForEach(TravelMode.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                        }
                        if document.samples.contains(where: { $0.gps.altitudeM == nil || $0.gps.speedMps == nil }) { Text("部分高度、速度或定位观测缺失；不会补造测量值。").font(.footnote).foregroundStyle(Theme.secondary) }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("导入预览").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") {
                        do { try recorder.commitImport(chosen.sorted().map { documents[$0] }); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.disabled(!ready) }
                }
                .onAppear { chosen = Set(documents.indices.filter { !recorder.isDuplicate(documents[$0]) }) }
        }
    }
}
struct NotesView: View {
    @EnvironmentObject var recorder: Recorder
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("旅程名称") { TextField("名称", text: $title) }
                Section("旅程笔记") { TextEditor(text: $notes).frame(minHeight: 200) }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("记录此刻").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") {
                        if recorder.updateNotes(notes, title: title) { dismiss() } else { error = recorder.message; recorder.message = nil }
                    } }
                }
        }.onAppear { title = recorder.displayed?.title ?? ""; notes = recorder.displayed?.notes ?? "" }
    }
}
