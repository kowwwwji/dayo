import DayoCore
import SwiftUI

/// 1 日分の予定と Todo を 1 本の時間軸で見せる。
/// 上部に終日・期限切れ、中央に時刻付き（グリッドかリスト）。期日なしのリマインダーは扱わない。
struct DayTimelineView: View {
    let model: DayTimelineModel
    /// 項目から詳細編集のモデルを作る。保存先（CalendarSource）は App が握る
    let makeEditor: @MainActor (TimelineItem) -> ItemEditorModel
    @AppStorage(TimelineStyle.storageKey) private var style: TimelineStyle = .grid
    @Environment(\.scenePhase) private var scenePhase
    @State private var editor: ItemEditorModel?
    @State private var showsSettings = false

    private var editing: ItemEditing {
        ItemEditing(editor: $editor, make: makeEditor)
    }

    var body: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            // Mac は日付をウィンドウタイトルに、移動と表示切替を入力欄の行に置くのでヘッダーは無い
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
            TimelineStylePicker(style: $style)
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 110)
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
            if !model.timeline.allDay.isEmpty {
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
            if model.hasLoaded, model.timeline.isEmpty {
                ContentUnavailableView("予定も Todo もありません", systemImage: "checkmark.circle")
            }
        }
    }

    @ViewBuilder
    private var timed: some View {
        switch style {
        case .grid:
            DayGridView(
                placements: model.placements,
                day: model.day,
                isToday: model.isToday,
                isLoaded: model.isLoadedForDay,
                editing: editing,
                onToggle: { item in Task { await model.toggleCompleted(item) } },
                onMove: { item, minute, span in Task { await model.move(item, toStartMinute: minute, span: span) } }
            )
        case .list:
            List(model.timeline.timed) { row($0) }
                .listStyle(.plain)
        }
    }

    private func row(_ item: TimelineItem, isOverdue: Bool = false) -> some View {
        TimelineRow(item: item, isOverdue: isOverdue, editing: editing) {
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
