import DayoCore
import SwiftUI

/// 予定と Todo を 1 本の時間軸で見せる。日表示は 1 列、週表示は 7 列。
/// 上部に終日・期限切れ、中央に時刻付きのグリッド。期日なしのリマインダーは扱わない。
struct DayTimelineView: View {
    let model: TimelineModel
    /// 項目から詳細編集のモデルを作る。保存先（CalendarSource）は App が握る
    let makeEditor: @MainActor (TimelineItem) -> ItemEditorModel
    /// 新規登録のモデルを作る。引数は開始日時と、終日として開くか
    let makeNewEditor: @MainActor (Date, Bool) -> ItemEditorModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var editor: ItemEditorModel?
    @State private var editorAnchor: String?
    @State private var showsSettings = false

    private var editing: ItemEditing {
        ItemEditing(editor: $editor, anchor: $editorAnchor, make: makeEditor, makeNew: makeNewEditor)
    }

    var body: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            // Mac は日付をウィンドウタイトルに、移動を入力欄の行に置くのでヘッダーは無い
            header
            Divider()
            #endif
            if let message = model.errorMessage {
                Text(message)
                    .font(.dayoSmall)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                Divider()
            }
            content
        }
        .task { await model.activate() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.activate() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            Task { await model.handleDayChanged() }
        }
    }

    #if os(iOS)
    private var header: some View {
        HStack(spacing: 12) {
            DayNavigationControls(model: model)
            Spacer()
            // iPhone には設定ウィンドウが無いのでここから開く（Mac は ⌘,）
            Button { showsSettings = true } label: {
                Image(systemName: "gearshape")
            }
            .sheet(isPresented: $showsSettings) {
                NavigationStack {
                    SettingsView()
                        .navigationTitle("設定")
                        .toolbar {
                            Button("完了") { showsSettings = false }
                        }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    #endif

    @ViewBuilder
    private var content: some View {
        switch model.access {
        case .granted:
            sections
        case .denied, .restricted:
            ContentUnavailableView(
                "カレンダーとリマインダーへのアクセスが必要です",
                systemImage: "lock",
                description: Text("システム設定のプライバシーで Dayo にフルアクセスを許可してください。")
            )
        case .notDetermined:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var sections: some View {
        VStack(spacing: 0) {
            if model.mode == .week {
                // 列と見出しがずれないよう、日付はモデルの範囲ではなく実際に並んでいる列から取る
                WeekHeaderView(days: model.columns.map(\.day), spans: model.allDaySpans, editing: editing) { item in
                    Task { await model.toggleCompleted(item) }
                }
                Divider()
            } else if !model.timeline.allDay.isEmpty {
                PinnedSection(title: "終日") {
                    FlowLayout(spacing: 6) {
                        ForEach(model.timeline.allDay) { item in
                            AllDayChip(item: item, editing: editing) {
                                Task { await model.toggleCompleted(item) }
                            }
                        }
                    }
                }
                Divider()
            }
            if !model.timeline.overdue.isEmpty {
                // 1 行およそ 40pt。多くても 3 行半で止めて残りはスクロール
                PinnedSection(title: "期限切れ", scrollHeight: min(CGFloat(model.timeline.overdue.count) * 40, 140)) {
                    ForEach(model.timeline.overdue) { row($0, isOverdue: true) }
                }
                Divider()
            }
            timed
        }
        .overlay {
            // 週表示は空でも曜日と時間軸を見せる
            if model.mode == .day, model.hasLoaded, model.timeline.isEmpty {
                ContentUnavailableView("予定も Todo もありません", systemImage: "checkmark.circle")
            }
        }
    }

    private var timed: some View {
DayGridView(
            columns: model.columns,
            isLoaded: model.isLoadedForRange,
            editing: editing,
            onToggle: { item in Task { await model.toggleCompleted(item) } },
            onMove: { move, span in
                Task {
                    await model.move(
                        move.item, from: move.originDay, toDay: move.targetDay, startMinute: move.minute, span: span
                    )
                }
            }
        )
    }

    private func row(_ item: TimelineItem, isOverdue: Bool = false) -> some View {
        TimelineRow(item: item, isOverdue: isOverdue, editing: editing, anchor: isOverdue ? "overdue" : nil) {
            Task { await model.toggleCompleted(item) }
        }
    }
}

/// グリッドの上に固定する小さなセクション。左にラベル、右に中身を置く（Apple カレンダーの「終日」行と同じ形）。
/// ラベル幅はグリッドの時刻ラベルに合わせ、縦の線が揃うようにする。
/// `scrollHeight` を渡すと行数に応じた高さ（上限あり）で内部スクロールする。渡さなければ中身の高さそのまま。
private struct PinnedSection<Content: View>: View {
    let title: String
    var scrollHeight: CGFloat?
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(title)
                .font(.dayoDetail)
                .foregroundStyle(.secondary)
                .frame(width: DayGridView.labelWidth - 6, alignment: .trailing)
                .padding(.top, 4)
            if let scrollHeight {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        content
                    }
                    // ScrollView は中身が狭いと中央に寄せるので、左端に固定する
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: scrollHeight)
            } else {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // 左余白は付けない。グリッドの時刻ラベルが左端 0 から始まるので、同じ x に揃える
        .padding(.trailing, DayGridView.trailingInset)
        .padding(.vertical, 6)
    }
}
