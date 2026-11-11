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
    @State private var board = TimelineDragBoard()
    /// 繰り返し予定の日時を変える前に、どの回に及ぶかを聞いている間の保留
    @State private var pendingChange: PendingChange?

    private struct PendingChange {
        let perform: (EditSpan) async -> Void
    }
    @State private var showsSettings = false
    /// キー操作の一覧を出しているか（Mac のみ）
    @State private var showsKeyHelp = false

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
        #if os(macOS)
        .overlay {
            if showsKeyHelp {
                KeyHelpView { showsKeyHelp = false }
            }
        }
        .onTimelineKey(isEnabled: model.access == .granted && editor == nil && pendingChange == nil, perform: handle)
        #endif
        .task { await model.activate() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.activate() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            Task { await model.handleDayChanged() }
        }
    }

    #if os(macOS)
    /// キー操作。何もしなかったキーは false を返して元の行き先へ流す。
    private func handle(_ key: TimelineKey) -> Bool {
        switch key {
        case .selectNext: model.selectNext()
        case .selectPrevious: model.selectPrevious()
        case .selectLeft: Task { await model.selectLeft() }
        case .selectRight: Task { await model.selectRight() }
        case .showToday: Task { await model.showToday() }
        case .showPrevious: Task { await model.showPrevious() }
        case .showNext: Task { await model.showNext() }
        case .toggleCompleted:
            guard model.selectedItem?.kind == .reminder else { return false }
            Task { await model.toggleSelectedCompleted() }
        case .openEditor:
            guard let selection = model.selection, let item = model.selectedItem else { return false }
            editing.open(item, at: selection.place.editorAnchor)
        case .toggleHelp: showsKeyHelp.toggle()
        case .clearSelection:
            // 一覧が出ていれば、まずそれを閉じる
            if showsKeyHelp {
                showsKeyHelp = false
                return true
            }
            guard model.selection != nil else { return false }
            model.clearSelection()
        }
        return true
    }
    #endif

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
            // 期限切れを上、終日を時間軸のすぐ上に置く。終日欄は時間軸とドラッグで行き来するので隣り合わせにする
            if !model.timeline.overdue.isEmpty {
                // 1 行およそ 40pt。多くても 3 行半で止めて残りはスクロール
                PinnedSection(
                    title: "期限切れ",
                    scrollHeight: min(CGFloat(model.timeline.overdue.count) * 40, 140),
                    leadingInset: 12,
                    scrollTarget: model.selection?.place == .overdue ? model.selection?.itemID : nil
                ) {
                    ForEach(model.timeline.overdue) { item in
                        row(item, isOverdue: true).id(item.id)
                    }
                }
                Divider()
            }
            // 終日欄は空でも出す。ダブルクリックでの登録と、時間軸からのドラッグの落とし先になるため
            if model.mode == .week {
                // 列と見出しがずれないよう、日付はモデルの範囲ではなく実際に並んでいる列から取る
                WeekHeaderView(
                    days: model.columns.map(\.day),
                    spans: model.allDaySpans,
                    selection: model.selection,
                    editing: editing,
                    board: board,
                    onToggle: { item in Task { await model.toggleCompleted(item) } },
                    onMoveDays: { item, days in
                        change(item) { await model.moveAllDay(item, byDays: days, span: $0) }
                    },
                    onMakeTimed: makeTimed
                )
            } else {
                dayAllDay
            }
            Divider()
            timed
        }
        .overlay { DragGhostView(board: board) }
        .coordinateSpace(name: TimelineDragBoard.space)
        .confirmationDialog(
            "繰り返しの予定です",
            isPresented: Binding(get: { pendingChange != nil }, set: { if !$0 { pendingChange = nil } }),
            titleVisibility: .visible,
            presenting: pendingChange
        ) { pending in
            Button("この回のみ") { Task { await pending.perform(.thisOccurrence) } }
            Button("以降すべて") { Task { await pending.perform(.futureOccurrences) } }
            Button("キャンセル", role: .cancel) {}
        } message: { _ in
            Text("どの回の日時を変えますか？")
        }
        .overlay {
            // 週表示は空でも曜日と時間軸を見せる
            if model.mode == .day, model.hasLoaded, model.timeline.isEmpty {
                ContentUnavailableView("予定も Todo もありません", systemImage: "checkmark.circle")
            }
        }
    }

    /// 日表示の終日欄で新規登録のエディタを開く場所のキー。
    private static let newAllDayAnchor = "allDay-new"

    /// 日表示の終日欄。チップを左から並べる。
    private var dayAllDay: some View {
        PinnedSection(title: "終日") {
            FlowLayout(spacing: 6) {
                ForEach(model.timeline.allDay) { item in
                    // 日表示は列が 1 つなので横には動かせない。時間軸へ落とすことだけできる
                    AllDayChip(
                        item: item,
                        editing: editing,
                        isSelected: model.selection == TimelineSelection(itemID: item.id, place: .allDay),
                        drag: AllDayChipDrag(
                            board: board,
                            onMoveDays: { _ in },
                            onMakeTimed: { day, minute in makeTimed(item, day, minute) }
                        )
                    ) {
                        Task { await model.toggleCompleted(item) }
                    }
                }
                NewItemChip(editing: editing, anchor: Self.newAllDayAnchor)
            }
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .topLeading)
            #if os(macOS)
            // 空いているところのダブルクリックで、この日の終日として登録を開く。チップより下なのでチップの上では反応しない
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(TapGesture(count: 2).onEnded {
                        editing.openNew(at: model.day, isAllDay: true, anchor: Self.newAllDayAnchor)
                    })
            }
            #endif
            // 時間軸からここへ落とした項目を終日にする
            .onFrameChange { board.allDayFrame = $0 }
        }
    }

    private var timed: some View {
        DayGridView(
            columns: model.columns,
            selection: model.selection,
            isLoaded: model.isLoadedForRange,
            editing: editing,
            board: board,
            onToggle: { item in Task { await model.toggleCompleted(item) } },
            onMove: { move, span in
                Task {
                    await model.move(
                        move.item, from: move.originDay, toDay: move.targetDay, startMinute: move.minute, span: span
                    )
                }
            },
            onMakeAllDay: { item, day in
                change(item) { await model.makeAllDay(item, onDay: day, span: $0) }
            }
        )
    }

    private func makeTimed(_ item: TimelineItem, _ day: Date, _ minute: Int) {
        change(item) { await model.makeTimed(item, onDay: day, startMinute: minute, span: $0) }
    }

    /// 日時を変える。繰り返しの予定は回ごとに分けて変えられるので、先に範囲を聞く。
    private func change(_ item: TimelineItem, _ perform: @escaping (EditSpan) async -> Void) {
        if item.kind == .event, item.hasRecurrence {
            pendingChange = PendingChange(perform: perform)
        } else {
            Task { await perform(.thisOccurrence) }
        }
    }

    private func row(_ item: TimelineItem, isOverdue: Bool = false) -> some View {
        TimelineRow(
            item: item,
            isOverdue: isOverdue,
            editing: editing,
            anchor: isOverdue ? TimelineSelection.Place.overdue.editorAnchor : nil,
            isSelected: isOverdue && model.selection == TimelineSelection(itemID: item.id, place: .overdue)
        ) {
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
    /// 左に空ける幅。ラベルが長くて左端に付いてしまうセクションで使う（その分、中身はグリッドの線より右へずれる）
    var leadingInset: CGFloat = 0
    /// 見えるところまでスクロールしたい行の id。`scrollHeight` を渡したときだけ効く
    var scrollTarget: String?
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(title)
                .font(.dayoDetail)
                .foregroundStyle(.secondary)
                .frame(width: DayGridView.labelWidth - 6, alignment: .trailing)
                .padding(.top, 4)
            if let scrollHeight {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            content
                        }
                        // ScrollView は中身が狭いと中央に寄せるので、左端に固定する
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: scrollTarget) { _, target in
                        if let target { proxy.scrollTo(target) }
                    }
                }
                .frame(height: scrollHeight)
            } else {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // 既定では左余白を付けない。グリッドの時刻ラベルが左端 0 から始まるので、同じ x に揃える
        .padding(.leading, leadingInset)
        .padding(.trailing, DayGridView.trailingInset)
        .padding(.vertical, 6)
    }
}
