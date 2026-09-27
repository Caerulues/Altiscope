import SwiftUI

struct JournalView: View {
    @EnvironmentObject var recorder: Recorder
    let openMap: () -> Void
    @State private var query = ""
    var records: [TrackSession] {
        var records = recorder.sessions
        if let active = recorder.active { records.removeAll { $0.id == active.id }; records.insert(active,at:0) }
        return records.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.notes.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                Text("YOUR LOGBOOK").smallLabel()
                HStack { Text("旅程日志").font(.system(size:30,weight:.semibold)); Spacer(); Text("\(records.count) 段旅程").font(.system(size:12)).foregroundStyle(Theme.secondary) }
                HStack(spacing:20) {
                    Metric(title:"累计里程",value:Display.distance(recorder.sessions.reduce(0) { $0+$1.distance }),unit:"km")
                    Metric(title:"累计记录",value:Display.number(recorder.sessions.reduce(0) { $0+$1.duration(at:recorder.now) } / 3600,decimals:1),unit:"h")
                }.panel()
                HStack { Image(systemName:"magnifyingglass"); TextField("搜索名称或笔记",text:$query).font(.system(size:14)) }.foregroundStyle(Theme.secondary).padding(14).background(Theme.panel,in:RoundedRectangle(cornerRadius:13))
                if records.isEmpty {
                    VStack(spacing:14) {
                        Image(systemName:"point.topleft.down.to.point.bottomright.curvepath").font(.system(size:38)).foregroundStyle(Theme.accent)
                        Text(query.isEmpty ? "第一段旅程，等你出发。" : "没有匹配的记录").font(.system(size:17,weight:.medium))
                        Text("记录保存在这台设备，无需账号。\n完成后可导出 GPX 和完整传感器数据。").font(.system(size:12)).multilineTextAlignment(.center).foregroundStyle(Theme.secondary)
                        Button("查看示例") { recorder.showDemo(); openMap() }.buttonStyle(.bordered)
                    }.frame(maxWidth:.infinity).padding(.vertical,45)
                }
                ForEach(records) { session in
                    Button { recorder.select(session); openMap() } label: {
                        HStack(spacing:15) {
                            Image(systemName:session.mode.symbol).font(.system(size:22)).foregroundStyle(Theme.accent).frame(width:48,height:54).background(Theme.accent.opacity(0.09),in:RoundedRectangle(cornerRadius:13))
                            VStack(alignment:.leading,spacing:7) {
                                Text(session.title).font(.system(size:15,weight:.medium)).lineLimit(1)
                                Text(session.startedAt.formatted(date:.abbreviated,time:.shortened)).font(.system(size:10)).foregroundStyle(Theme.secondary)
                                Text("\(Display.distance(session.distance)) km  ·  \(Display.duration(session.duration(at:recorder.now)))").font(.system(size:11,design:.monospaced)).foregroundStyle(Theme.accent)
                            }; Spacer(minLength:0); Image(systemName:"chevron.right").font(.system(size:11)).foregroundStyle(Theme.secondary)
                        }.panel()
                    }.buttonStyle(.plain)
                }
            }.padding(20)
        }.scrollIndicators(.hidden)
    }
}
struct NotesView: View {
    @EnvironmentObject var recorder: Recorder
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    var body: some View {
        NavigationStack {
            Form { Section("旅程名称") { TextField("名称",text:$title) }; Section("旅程笔记") { TextEditor(text:$notes).frame(minHeight:200) } }
                .navigationTitle("记录此刻").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement:.confirmationAction) { Button("保存") { recorder.updateNotes(notes,title:title); dismiss() } } }
                .onAppear { title = recorder.displayed?.title ?? ""; notes = recorder.displayed?.notes ?? "" }
        }.preferredColorScheme(.dark)
    }
}
